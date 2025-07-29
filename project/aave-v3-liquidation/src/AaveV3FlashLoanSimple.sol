// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPoolAddressesProvider} from 'aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from 'aave-v3-origin/src/contracts/interfaces/IPool.sol';
import {FlashLoanSimpleReceiverBase} from 'aave-v3-origin/src/contracts/misc/flashloan/base/FlashLoanSimpleReceiverBase.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IFlashLoanSimpleReceiver} from 'aave-v3-origin/src/contracts/misc/flashloan/interfaces/IFlashLoanSimpleReceiver.sol';
// import {IAggregationRouterV5} from './interfaces/IAggregationRouterV5.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';

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

    // 1inch 聚合器地址
    address public immutable AGGREGATION_ROUTER;
    address public immutable WETH;

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
        address _aggregationRouter,
        address _weth,
        uint256 _builderPaymentPercentage
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
        require(_addressProvider != address(0), 'AaveV3FlashLoan: invalid address provider');
        require(_aggregationRouter != address(0), 'AaveV3FlashLoan: invalid aggregation router');
        require(_weth != address(0), 'AaveV3FlashLoan: invalid WETH');
        require(_builderPaymentPercentage <= MAX_BUILDER_PAYMENT_PERCENTAGE, 'AaveV3FlashLoan: invalid builder payment percentage');
        
        owner = msg.sender;
        AGGREGATION_ROUTER = _aggregationRouter;
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
        bytes calldata collateralToDebtSwapData, // 抵押品 -> 债务资产的交换数据
        bytes calldata debtToWethSwapData,      // 债务资产 -> WETH的交换数据（当债务资产不是WETH时使用）
        uint256 deadline                        // 交易截止时间
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
            collateralToDebtSwapData,
            debtToWethSwapData,
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
            bytes memory collateralToDebtSwapData,
            bytes memory debtToWethSwapData,
            uint256 deadline,
            bool isDebtAssetWeth
        ) = abi.decode(params, (address, address, bool, bytes, bytes, uint256, bool));

        require(block.timestamp <= deadline, 'AaveV3FlashLoan: deadline expired');

        // 执行清算流程
        _executeLiquidation(
            asset,
            amount,
            premium,
            collateralAsset,
            user,
            receiveAToken,
            collateralToDebtSwapData,
            debtToWethSwapData,
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
        bytes memory collateralToDebtSwapData,
        bytes memory debtToWethSwapData,
        bool isDebtAssetWeth
    ) private {
        // 授权 Aave 使用债务资产
        IERC20(asset).approve(address(POOL), amount + premium);

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
            collateralToDebtSwapData
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
            debtToWethSwapData,
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
        bytes memory swapData
    ) private {
        // 授权 1inch 使用抵押品（先重置授权）
        IERC20(collateralAsset).approve(AGGREGATION_ROUTER, 0);
        IERC20(collateralAsset).approve(AGGREGATION_ROUTER, collateralBalance);

        // 使用 1inch 将抵押品换成债务资产
        (bool success, ) = AGGREGATION_ROUTER.call(swapData);
        require(success, 'AaveV3FlashLoan: collateral to debt swap failed');
    }

    function _handleRemainingProfit(
        address asset,
        bytes memory swapData,
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
                // 如果债务资产不是 WETH，需要通过 DEX 兑换成 WETH
                // 授权 1inch 使用剩余的债务资产（先重置授权）
                IERC20(asset).approve(AGGREGATION_ROUTER, 0);
                IERC20(asset).approve(AGGREGATION_ROUTER, remainingDebtAsset);

                // 使用 1inch 将剩余的债务资产兑换成 WETH
                (bool success, ) = AGGREGATION_ROUTER.call(swapData);
                require(success, 'AaveV3FlashLoan: debt to WETH swap failed');

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
    receive() external payable {}
}
