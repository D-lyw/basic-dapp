// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPoolAddressesProvider} from 'aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from 'aave-v3-origin/src/contracts/interfaces/IPool.sol';
import {FlashLoanSimpleReceiverBase} from 'aave-v3-origin/src/contracts/misc/flashloan/base/FlashLoanSimpleReceiverBase.sol';
import {IERC20, IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IFlashLoanSimpleReceiver} from 'aave-v3-origin/src/contracts/misc/flashloan/interfaces/IFlashLoanSimpleReceiver.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';

// Uniswap imports
import {UniversalRouter} from '@uniswap/universal-router/contracts/UniversalRouter.sol';
import {Commands} from '@uniswap/universal-router/contracts/libraries/Commands.sol';
import {IPermit2} from '@uniswap/permit2/src/interfaces/IPermit2.sol';
import {IPriceOracleGetter} from 'aave-v3-origin/src/contracts/interfaces/IPriceOracleGetter.sol';

// Uniswap V4 相关结构体定义
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct ExactInputSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 amountIn;
    uint128 amountOutMinimum;
    bytes hookData;
}

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
 *      4. 将抵押品在 DEX 上换成债务资产
 *      5. 偿还闪电贷
 *      6. 处理剩余债务资产：
 *         - 如果债务资产是 WETH：直接转换为 ETH
 *         - 如果债务资产不是 WETH：在 DEX 上兑换成 WETH 再转换为 ETH
 *      7. 将部分 ETH 支付给 Builder 作为贿选费用
 *      8. 将剩余 ETH 发送给合约拥有者
 */
contract AaveV3FlashLoanSimple is FlashLoanSimpleReceiverBase, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // 常量定义
    uint16 private constant REFERRAL_CODE = 0;
    uint256 private constant MIN_LIQUIDATION_AMOUNT = 1;
    uint256 private constant MAX_BUILDER_PAYMENT_PERCENTAGE = 99; // 最大 Builder 支付比例 99%

    // Uniswap Universal Router 地址
    UniversalRouter public immutable UNIVERSAL_ROUTER;
    IPermit2 public immutable PERMIT2;
    address public immutable WETH;
    IPriceOracleGetter public immutable ORACLE;

    address public immutable owner;
    uint256 public builderPaymentPercentage; // Builder 支付比例

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

    event EmergencyPaused(
        address indexed caller,
        uint256 timestamp
    );

    event EmergencyUnpaused(
        address indexed caller,
        uint256 timestamp
    );

    modifier onlyOwner() {
        require(msg.sender == owner, 'AaveV3FlashLoan: caller is not the owner');
        _;
    }

    constructor(
        address _addressProvider,
        address _universalRouter,
        address _permit2,
        address _weth,
        uint256 _builderPaymentPercentage
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
        require(_addressProvider != address(0), 'AaveV3FlashLoan: invalid address provider');
        require(_universalRouter != address(0), 'AaveV3FlashLoan: invalid universal router');
        require(_permit2 != address(0), 'AaveV3FlashLoan: invalid permit2');
        require(_weth != address(0), 'AaveV3FlashLoan: invalid WETH');
        require(_builderPaymentPercentage <= MAX_BUILDER_PAYMENT_PERCENTAGE, 'AaveV3FlashLoan: invalid builder payment percentage');

        // 获取 Aave Oracle 地址
        ORACLE = IPriceOracleGetter(IPoolAddressesProvider(_addressProvider).getPriceOracle());
        
        owner = msg.sender;
        UNIVERSAL_ROUTER = UniversalRouter(payable(_universalRouter));
        PERMIT2 = IPermit2(_permit2);
        WETH = _weth;
        builderPaymentPercentage = _builderPaymentPercentage;
    }

    /**
     * @notice 更新 Builder 支付比例
     * @param _newPercentage 新的支付比例
     */
    function updateBuilderPaymentPercentage(uint256 _newPercentage) external onlyOwner whenNotPaused {
        require(_newPercentage <= MAX_BUILDER_PAYMENT_PERCENTAGE, 'AaveV3FlashLoan: invalid builder payment percentage');
        uint256 oldPercentage = builderPaymentPercentage;
        builderPaymentPercentage = _newPercentage;
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
        uint256 deadline                             // 交易截止时间
    ) external onlyOwner whenNotPaused nonReentrant {
        require(collateralAsset != address(0), 'AaveV3FlashLoan: invalid collateral asset');
        require(debtAsset != address(0), 'AaveV3FlashLoan: invalid debt asset');
        require(user != address(0), 'AaveV3FlashLoan: invalid user address');
        require(debtToCover >= MIN_LIQUIDATION_AMOUNT, 'AaveV3FlashLoan: invalid debt amount');
        require(deadline > block.timestamp, 'AaveV3FlashLoan: deadline expired');

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
            debtToCover,
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
        require(initiator == address(this), 'AaveV3FlashLoan: unauthorized initiator');

        // 解码参数
        (
            address collateralAsset,
            address user,
            bool receiveAToken,
            uint256 deadline,
            bool isDebtAssetWeth
        ) = abi.decode(params, (address, address, bool, uint256, bool));

        require(block.timestamp <= deadline, 'AaveV3FlashLoan: deadline expired');

        // 执行清算流程
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
        // 再次检查用户的健康值是否小于清算阈值
        (, , , , , uint256 healthFactor) = POOL.getUserAccountData(user);
        require(
            healthFactor < 1e18,
            'AaveV3FlashLoan: user health factor above threshold'
        );
        // 授权 Aave 使用债务资产
        IERC20(asset).forceApprove(address(POOL), amount + premium);

        // 执行清算
        POOL.liquidationCall(
            collateralAsset,
            asset,
            user,
            amount,
            receiveAToken
        );

        // 获取清算获得的抵押品数量
        uint256 collateralBalance = IERC20(collateralAsset).balanceOf(address(this));
        require(collateralBalance > 0, 'AaveV3FlashLoan: no collateral received');

        // 处理抵押品兑换
        _handleCollateralSwap(
            collateralAsset,
            collateralBalance,
            asset,
            amount + premium // 需要兑换的债务资产数量（包含闪电贷费用）
        );

        // 检查是否有足够的债务资产来偿还闪电贷
        uint256 debtAssetBalance = IERC20(asset).balanceOf(address(this));
        require(
            debtAssetBalance >= amount + premium,
            'AaveV3FlashLoan: insufficient debt asset to repay flash loan'
        );

        // 处理剩余利润
        _handleRemainingProfit(
            asset,
            collateralAsset,
            user,
            amount,
            collateralBalance,
            premium,
            isDebtAssetWeth
        );
    }

    function _handleCollateralSwap(
        address collateralAsset,
        uint256 collateralBalance,
        address debtAsset,
        uint256 requiredDebtAmount
    ) private {
        // 授权 Permit2 使用抵押品
        IERC20(collateralAsset).forceApprove(address(PERMIT2), collateralBalance);

        // 构建 V4_SWAP 命令
        bytes memory commands = new bytes(1);
        commands[0] = bytes1(0x10); // V4_SWAP command

        // 构建 PoolKey
        PoolKey memory poolKey = PoolKey({
            currency0: collateralAsset,
            currency1: debtAsset,
            fee: 3000, // 0.3% fee tier
            tickSpacing: 60,
            hooks: address(0)
        });

        // 构建 ExactInputSingleParams
        ExactInputSingleParams memory params = ExactInputSingleParams({
            poolKey: poolKey,
            zeroForOne: _determineZeroForOne(collateralAsset, debtAsset), // collateralAsset -> debtAsset
            amountIn: uint128(collateralBalance),
            amountOutMinimum: uint128(requiredDebtAmount),
            hookData: ""
        });

        // 编码参数
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(params);

        // 执行兑换
        UNIVERSAL_ROUTER.execute(commands, inputs);
    }

    function _handleRemainingProfit(
        address asset,
        address collateralAsset,
        address user,
        uint256 amount,
        uint256 collateralBalance,
        uint256 premium,
        bool isDebtAssetWeth
    ) private {
        uint256 remainingDebtAsset = IERC20(asset).balanceOf(address(this));
        
        if (remainingDebtAsset > 0) {
            // 记录兑换前的 ETH 余额
            uint256 ethBalanceBefore = address(this).balance;
            
            if (isDebtAssetWeth) {
                // 如果债务资产就是 WETH，直接转换为 ETH
                IWETH(WETH).withdraw(remainingDebtAsset);
            } else {
                // 如果债务资产不是 WETH，需要通过 Universal Router 兑换成 WETH
                // 授权 Permit2 使用剩余的债务资产
                IERC20(asset).forceApprove(address(PERMIT2), remainingDebtAsset);

                // 构建 V4_SWAP 命令
                bytes memory commands = new bytes(1);
                commands[0] = bytes1(0x10); // V4_SWAP command

                // 构建 PoolKey
                PoolKey memory poolKey = PoolKey({
                    currency0: asset,
                    currency1: WETH,
                    fee: 3000, // 0.3% fee tier
                    tickSpacing: 60,
                    hooks: address(0)
                });

                // 构建 ExactInputSingleParams
                ExactInputSingleParams memory params = ExactInputSingleParams({
                    poolKey: poolKey,
                    zeroForOne: _determineZeroForOne(asset, WETH), // asset -> WETH
                    amountIn: uint128(remainingDebtAsset),
                    // 使用 Aave Oracle 获取代币价格并计算最小 WETH 输出
                    // 计算顺序：
                    // 1. remainingDebtAsset * assetPrice * 95% (应用滑点保护)
                    // 2. 除以 wethPrice
                    // 3. 调整代币精度：* WETH.decimals / asset.decimals
                    amountOutMinimum: uint128(
                        (remainingDebtAsset * ORACLE.getAssetPrice(asset) * 95 / 100) /
                        ORACLE.getAssetPrice(WETH) *
                        (10 ** IERC20Metadata(WETH).decimals()) /
                        (10 ** IERC20Metadata(asset).decimals())
                    ),
                    hookData: ""
                });

                // 编码参数
                bytes[] memory inputs = new bytes[](1);
                inputs[0] = abi.encode(params);

                // 执行兑换
                UNIVERSAL_ROUTER.execute(commands, inputs);

                // 将 WETH 转换成 ETH
                IWETH(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));
            }

            // 计算从兑换中获得的 ETH（只计算新增的 ETH）
            uint256 ethBalanceAfter = address(this).balance;
            uint256 profitEth = ethBalanceAfter - ethBalanceBefore;
            
            if (profitEth > 0) {
                uint256 builderPayment = (profitEth * builderPaymentPercentage) / 100;
                
                if (builderPayment > 0) {
                    // 支付给 Builder
                    (bool success, ) = block.coinbase.call{value: builderPayment}(new bytes(0));
                    if (!success) {
                        emit BuilderPaymentFailed(block.coinbase, builderPayment, 'Builder payment failed');
                    }
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
                    0, // owner 不立即获得支付，ETH 留在合约中
                    block.timestamp
                );
            }
        }
    }

    /**
     * @notice 提取合约中的资产
     * @param token 要提取的代币地址
     * @param amount 要提取的数量
     */
    function withdrawToken(address token, uint256 amount) external onlyOwner whenNotPaused {
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
        
        emit TokensWithdrawn(address(0), owner, withdrawAmount, block.timestamp);
    }

    /**
     * @dev Allows receiving ETH
     */
    /**
     * @dev 根据代币地址大小确定交易方向
     * @param fromToken 源代币地址
     * @param toToken 目标代币地址
     * @return 如果 fromToken 是内部的 token0，则返回 true；如果 fromToken 是内部的 token1，则返回 false
     */
    function _determineZeroForOne(address fromToken, address toToken) internal pure returns (bool) {
        return uint160(fromToken) < uint160(toToken);
    }

    /**
     * @notice 使用 Permit2 授权代币
     * @param token 要授权的代币地址
     * @param amount 授权数量
     * @param expiration 授权过期时间
     */
    function approveTokenWithPermit2(
        address token,
        uint160 amount,
        uint48 expiration
    ) external onlyOwner whenNotPaused {
        // 首先授权 Permit2 使用代币
        IERC20(token).forceApprove(address(PERMIT2), type(uint256).max);
        // 然后通过 Permit2 授权 UniversalRouter
        PERMIT2.approve(token, address(UNIVERSAL_ROUTER), amount, expiration);
    }

    receive() external payable {}
}
