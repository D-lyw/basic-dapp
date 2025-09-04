// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IPoolAddressesProvider} from 'aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from 'aave-v3-origin/src/contracts/interfaces/IPool.sol';
import {FlashLoanSimpleReceiverBase} from 'aave-v3-origin/src/contracts/misc/flashloan/base/FlashLoanSimpleReceiverBase.sol';
import {IERC20, IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IFlashLoanSimpleReceiver} from 'aave-v3-origin/src/contracts/misc/flashloan/interfaces/IFlashLoanSimpleReceiver.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';
import {DataTypes} from 'aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol';

// Uniswap imports
import {IPriceOracleGetter} from 'aave-v3-origin/src/contracts/interfaces/IPriceOracleGetter.sol';
import './MultiVersionUniswapRouter.sol';

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;
}

/**
 * @title Liquidation Aave v3 by flashloan
 * @author
 * @notice 使用闪电贷进行 Aave V3 清算的合约
 * @dev 该合约通过闪电贷获取资金，用于清算 Aave V3 协议中的不良债务
 *      清算流程：
 *      1. 通过闪电贷借入债务资产
 *      2. 使用借入的资产进行清算
 *      3. 获得抵押品
 *      4. 将抵押品通过 MultiVersionUniswapRouter 换成债务资产（自动选择 V2/V3/V4 最优路径）
 *      5. 偿还闪电贷
 *      6. 处理剩余债务资产：
 *         - 如果债务资产是 WETH：直接转换为 ETH
 *         - 如果债务资产不是 WETH：通过 MultiVersionUniswapRouter 兑换成 WETH 再转换为 ETH
 *      7. 将部分 ETH 支付给 Builder 作为贿选费用
 *      8. 将剩余 ETH 发送给合约拥有者
 */
contract AaveV3FlashLoanSimple is
    FlashLoanSimpleReceiverBase,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;

    // 基础常量
    uint16 private constant REFERRAL_CODE = 0;
    uint256 private constant MAX_BUILDER_PAYMENT_PERCENTAGE = 99; // 最大 Builder 支付比例 99%
    uint256 private constant SLIPPAGE_TOLERANCE = 95; // 滑点容忍度 95%
    uint256 private constant PERCENTAGE_BASE = 100; // 百分比基数

    // MultiVersionUniswapRouter 地址
    MultiVersionUniswapRouter public immutable MULTI_ROUTER;
    address public immutable WETH;
    IPriceOracleGetter public immutable ORACLE;

    address public immutable owner;
    uint96 public builderPaymentPercentage; // Builder 支付比例 (打包优化: uint96 + address = 32字节)

    // 事件定义
    event LiquidationExecuted(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 collateralReceived,
        uint256 premium,
        uint256 profit,
        uint256 builderPayment,
        uint256 ownerPayment,
        uint256 timestamp
    );

    event TokensWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event BuilderPaymentFailed(
        address indexed builder,
        uint256 amount,
        string reason
    );

    event BuilderPaymentPercentageUpdated(
        uint256 oldPercentage,
        uint256 newPercentage
    );

    event EmergencyPaused(address indexed caller, uint256 timestamp);

    event EmergencyUnpaused(address indexed caller, uint256 timestamp);

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            'AaveV3FlashLoan: caller is not the owner'
        );
        _;
    }

    constructor(
        address _addressProvider,
        address _multiRouter,
        address _weth,
        uint256 _builderPaymentPercentage
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
        require(
            _addressProvider != address(0),
            'AaveV3FlashLoan: invalid address provider'
        );
        require(
            _multiRouter != address(0),
            'AaveV3FlashLoan: invalid multi router'
        );
        require(_weth != address(0), 'AaveV3FlashLoan: invalid WETH');
        require(
            _builderPaymentPercentage <= MAX_BUILDER_PAYMENT_PERCENTAGE,
            'AaveV3FlashLoan: invalid builder payment percentage'
        );

        // 获取 Aave Oracle 地址
        ORACLE = IPriceOracleGetter(
            IPoolAddressesProvider(_addressProvider).getPriceOracle()
        );

        owner = msg.sender;
        MULTI_ROUTER = MultiVersionUniswapRouter(payable(_multiRouter));
        WETH = _weth;
        builderPaymentPercentage = uint96(_builderPaymentPercentage);
    }

    /**
     * @notice 更新 Builder 支付比例
     * @param _newPercentage 新的支付比例
     */
    function updateBuilderPaymentPercentage(
        uint256 _newPercentage
    ) external onlyOwner whenNotPaused {
        require(
            _newPercentage <= MAX_BUILDER_PAYMENT_PERCENTAGE,
            'AaveV3FlashLoan: invalid builder payment percentage'
        );
        uint256 oldPercentage = builderPaymentPercentage;
        builderPaymentPercentage = uint96(_newPercentage);
        emit BuilderPaymentPercentageUpdated(oldPercentage, _newPercentage);
    }

    /**
     * @notice 紧急暂停合约
     */
    function pause() external onlyOwner {
        _pause();
        emit EmergencyPaused(msg.sender, block.timestamp);
    }

    /**
     * @notice 解除合约暂停
     */
    function unpause() external onlyOwner {
        _unpause();
        emit EmergencyUnpaused(msg.sender, block.timestamp);
    }

    function executeLiquidation(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken,
        uint256 deadline, // 交易截止时间
        bool useMaxDebt // 是否使用最大债务清算
    ) external onlyOwner whenNotPaused nonReentrant {
        require(
            collateralAsset != address(0),
            'AaveV3FlashLoan: invalid collateral asset'
        );
        require(debtAsset != address(0), 'AaveV3FlashLoan: invalid debt asset');
        require(user != address(0), 'AaveV3FlashLoan: invalid user address');
        
        // 最早检查用户健康因子，避免不必要的后续计算和外部调用
        (, , , , , uint256 healthFactor) = POOL.getUserAccountData(user);
        require(
            healthFactor < 1e18,
            'AaveV3FlashLoan: user health factor above threshold'
        );
        
        require(
            collateralAsset != debtAsset,
            'AaveV3FlashLoan: collateral and debt cannot be same asset'
        );
        require(
            deadline > block.timestamp,
            'AaveV3FlashLoan: deadline expired'
        );

        uint256 actualDebtToCover = debtToCover;

        // 如果使用最大债务清算，获取用户全部债务余额
        // 让 Aave 协议自己决定实际清算数量，我们在后续处理未消耗的余额
        if (useMaxDebt) {
            actualDebtToCover = _getUserDebtBalance(debtAsset, user);
            require(
                actualDebtToCover > 0,
                'AaveV3FlashLoan: user has no debt in this asset'
            );
        }

        // 检查债务资产是否为 WETH
        bool isDebtAssetWeth = (debtAsset == WETH);

        // 获取闪电贷
        bytes memory params = abi.encode(
            collateralAsset,
            user,
            receiveAToken,
            deadline,
            isDebtAssetWeth
        );

        POOL.flashLoanSimple(
            address(this),
            debtAsset,
            actualDebtToCover,
            params,
            REFERRAL_CODE
        );
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(POOL), 'AaveV3FlashLoan: unauthorized');
        require(
            initiator == address(this),
            'AaveV3FlashLoan: unauthorized initiator'
        );

        // 解码参数
        (
            address collateralAsset,
            address user,
            bool receiveAToken,
            uint256 deadline,
            bool isDebtAssetWeth
        ) = abi.decode(params, (address, address, bool, uint256, bool));

        require(
            block.timestamp <= deadline,
            'AaveV3FlashLoan: deadline expired'
        );

        // 预计算总授权金额（清算 + 闪电贷还款）并一次性授权
        // 这样可以减少 forceApprove 调用次数
        uint256 totalAuthAmount = amount + (amount + premium);
        IERC20(asset).forceApprove(address(POOL), totalAuthAmount);

        // 执行清算
        _executeLiquidation(
            asset,
            amount,
            premium,
            collateralAsset,
            user,
            receiveAToken,
            isDebtAssetWeth
        );

        return true;
    }

    function _executeLiquidation(
        address asset,
        uint256 amount,
        uint256 premium,
        address collateralAsset,
        address user,
        bool receiveAToken,
        bool isDebtAssetWeth
    ) private {
        // 记录清算前的债务资产余额
        uint256 debtAssetBalanceBefore = IERC20(asset).balanceOf(address(this));

        // 授权已在 executeOperation 中完成，无需重复授权

        // 执行清算 - Aave 会根据抵押资产限制决定实际清算数量
        POOL.liquidationCall(
            collateralAsset,
            asset,
            user,
            amount,
            receiveAToken
        );

        // 计算实际消耗的债务资产数量
        uint256 debtAssetBalanceAfter = IERC20(asset).balanceOf(address(this));
        uint256 actualDebtUsed = debtAssetBalanceBefore - debtAssetBalanceAfter;

        // 获取清算获得的抵押品数量
        uint256 collateralBalance = IERC20(collateralAsset).balanceOf(
            address(this)
        );
        require(
            collateralBalance > 0,
            'AaveV3FlashLoan: no collateral received'
        );

        // 计算需要偿还的总金额（实际使用的债务 + 闪电贷费用）
        // 在部分清算场景下，actualDebtUsed 可能小于 amount，还有未消耗的闪电贷余额
        uint256 totalRepayAmount = actualDebtUsed + premium;

        // 处理抵押品兑换
        _handleCollateralSwap(
            collateralAsset,
            collateralBalance,
            asset,
            totalRepayAmount
        );

        // 检查是否有足够的债务资产来偿还闪电贷
        uint256 finalDebtAssetBalance = IERC20(asset).balanceOf(address(this));
        require(
            finalDebtAssetBalance >= amount + premium,
            'AaveV3FlashLoan: insufficient debt asset to repay flash loan'
        );

        // 计算偿还闪电贷后的剩余资产
        uint256 remainingAfterRepayment = finalDebtAssetBalance - (amount + premium);
        
        // 只有在有剩余资产时才处理利润
        if (remainingAfterRepayment > 0) {
            _handleRemainingProfit(
                asset,
                collateralAsset,
                user,
                amount,
                collateralBalance,
                premium,
                isDebtAssetWeth,
                remainingAfterRepayment
            );
        }
    }

    function _handleCollateralSwap(
        address collateralAsset,
        uint256 collateralBalance,
        address debtAsset,
        uint256 requiredDebtAmount
    ) private {
        // 安全检查
        require(
            collateralAsset != debtAsset,
            'AaveV3FlashLoan: same asset swap not allowed'
        );

        // 授权 MultiVersionUniswapRouter 使用抵押品
        IERC20(collateralAsset).forceApprove(
            address(MULTI_ROUTER),
            collateralBalance
        );

        // 执行兑换，使用多版本路由器自动选择最优路径
        try MULTI_ROUTER.swapExactTokensForTokens(
            collateralAsset,
            debtAsset,
            collateralBalance,
            requiredDebtAmount,
            address(this)
        ) returns (uint256 amountOut) {
            // 验证兑换是否成功获得足够的债务资产
            require(
                amountOut >= requiredDebtAmount,
                'AaveV3FlashLoan: insufficient debt asset after swap'
            );
        } catch Error(string memory reason) {
            revert(
                string(
                    abi.encodePacked(
                        'AaveV3FlashLoan: Multi-version swap failed - ',
                        reason
                    )
                )
            );
        } catch {
            revert('AaveV3FlashLoan: Multi-version swap failed with unknown error');
        }
    }

    function _handleRemainingProfit(
        address asset,
        address collateralAsset,
        address user,
        uint256 amount,
        uint256 collateralBalance,
        uint256 premium,
        bool isDebtAssetWeth,
        uint256 remainingDebtAsset
    ) private {
        // 缓存状态变量到内存以节省 gas
        uint256 cachedBuilderPaymentPercentage = builderPaymentPercentage;
        
        // 记录兑换前的 ETH 余额
        uint256 ethBalanceBefore = address(this).balance;

        if (isDebtAssetWeth) {
            // 如果债务资产就是 WETH，直接转换为 ETH
            IWETH(WETH).withdraw(remainingDebtAsset);
        } else {
            // 优化：预先获取价格和精度信息，合并验证
            uint256 inputPrice = ORACLE.getAssetPrice(asset);
            uint256 outputPrice = ORACLE.getAssetPrice(WETH);
            
            // 合并价格验证，减少条件检查次数
            require(
                inputPrice > 0 && outputPrice > 0,
                'AaveV3FlashLoan: invalid token prices'
            );
            
            // 批量获取精度信息
            uint256 inputDecimals = IERC20Metadata(asset).decimals();
            uint256 outputDecimals = IERC20Metadata(WETH).decimals();

            // 优化：预计算常用值，减少重复计算
            uint256 inputPriceScaled = inputPrice * (10 ** outputDecimals);
            uint256 outputPriceScaled = outputPrice * (10 ** inputDecimals);
            
            // 计算理论上的输出金额（优化版本）
            uint256 theoreticalAmountOut = (remainingDebtAsset * inputPriceScaled) / outputPriceScaled;

            // 应用 5% 的滑点保护
            uint256 minWethOut = (theoreticalAmountOut * SLIPPAGE_TOLERANCE) / PERCENTAGE_BASE;

            // 授权 MultiVersionUniswapRouter 使用剩余的债务资产
            IERC20(asset).forceApprove(address(MULTI_ROUTER), remainingDebtAsset);

            // 使用 MultiVersionUniswapRouter 执行兑换
            try MULTI_ROUTER.swapExactTokensForTokens(
                asset,
                WETH,
                remainingDebtAsset,
                minWethOut,
                address(this)
            ) returns (uint256 wethReceived) {
                // 将 WETH 转换成 ETH
                IWETH(WETH).withdraw(wethReceived);
            } catch Error(string memory reason) {
                revert(
                    string(
                        abi.encodePacked(
                            'AaveV3FlashLoan: Multi-version WETH swap failed - ',
                            reason
                        )
                    )
                );
            } catch {
                revert(
                    'AaveV3FlashLoan: Multi-version WETH swap failed with unknown error'
                );
            }
        }

        // 计算从兑换中获得的 ETH（只计算新增的 ETH）
        uint256 ethBalanceAfter = address(this).balance;
        uint256 profitEth = ethBalanceAfter - ethBalanceBefore;

        // 优化：提前检查是否有利润，避免不必要的计算
        if (profitEth > 0 && cachedBuilderPaymentPercentage > 0) {
            // 只有当 cachedBuilderPaymentPercentage > 0 时才计算 builderPayment
            uint256 builderPayment = (profitEth * cachedBuilderPaymentPercentage) / PERCENTAGE_BASE;
            
            // 支付给 Builder
            (bool success, ) = block.coinbase.call{value: builderPayment}(new bytes(0));
            if (!success) {
                emit BuilderPaymentFailed(
                    block.coinbase,
                    builderPayment,
                    'Builder payment failed'
                );
            }
            emit LiquidationExecuted(
                collateralAsset,
                asset,
                user,
                amount,
                collateralBalance,
                premium,
                remainingDebtAsset,
                builderPayment,
                profitEth, 
                block.timestamp
            );
        } else {
             emit LiquidationExecuted(
                collateralAsset,
                asset,
                user,
                amount,
                collateralBalance,
                premium,
                remainingDebtAsset,
                0,
                profitEth, 
                block.timestamp
            );
        }
    }

    /**
     * @dev Allows receiving ETH
     */
    receive() external payable {}

    /**
     * @notice 提取合约中的资产
     * @param token 要提取的代币地址
     * @param amount 要提取的数量
     */
    function withdrawToken(
        address token,
        uint256 amount
    ) external onlyOwner whenNotPaused {
        require(token != address(0), 'AaveV3FlashLoan: invalid token address');
        require(amount > 0, 'AaveV3FlashLoan: invalid amount');

        IERC20(token).safeTransfer(owner, amount);
        emit TokensWithdrawn(token, owner, amount, block.timestamp);
    }

    /**
     * @notice 提取合约中的 ETH
     * @param amount 要提取的数量，如果为 0 或大于余额则提取全部
     */
    function withdrawETH(uint256 amount) external onlyOwner whenNotPaused {
        uint256 balance = address(this).balance;
        require(balance > 0, 'AaveV3FlashLoan: no ETH to withdraw');

        uint256 withdrawAmount;
        if (amount == 0 || amount >= balance) {
            withdrawAmount = balance;
        } else {
            withdrawAmount = amount;
        }

        (bool success, ) = owner.call{value: withdrawAmount}('');
        require(success, 'AaveV3FlashLoan: ETH transfer failed');

        emit TokensWithdrawn(
            address(0),
            owner,
            withdrawAmount,
            block.timestamp
        );
    }

    /**
     * @notice 获取用户在指定债务资产中的实际债务余额
     * @param debtAsset 债务资产地址
     * @param user 用户地址
     * @return 用户的实际债务余额
     */
    function _getUserDebtBalance(
        address debtAsset,
        address user
    ) internal view returns (uint256) {
        // 获取债务资产的储备数据
        DataTypes.ReserveDataLegacy memory debtReserveData = POOL
            .getReserveData(debtAsset);

        // 返回用户在该债务资产中的实际债务余额
        return IERC20(debtReserveData.variableDebtTokenAddress).balanceOf(user);
    }
}
