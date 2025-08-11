// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IPoolAddressesProvider} from "aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {FlashLoanSimpleReceiverBase} from "aave-v3-origin/src/contracts/misc/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanSimpleReceiver} from "aave-v3-origin/src/contracts/misc/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {DataTypes} from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";

// Uniswap imports
import {UniversalRouter} from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IPriceOracleGetter} from "aave-v3-origin/src/contracts/interfaces/IPriceOracleGetter.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

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
contract AaveV3FlashLoanSimple is
    FlashLoanSimpleReceiverBase,
    ReentrancyGuard,
    Pausable
{
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    // 基础常量
    uint16 private constant REFERRAL_CODE = 0;
    uint256 private constant MAX_BUILDER_PAYMENT_PERCENTAGE = 99; // 最大 Builder 支付比例 99%

    // Uniswap V4 费率对应的 tickSpacing
    uint24 private constant FEE_LOW = 100; // 0.01%
    uint24 private constant FEE_MEDIUM = 500; // 0.05%
    uint24 private constant FEE_HIGH = 3000; // 0.3%
    uint24 private constant FEE_VERY_HIGH = 10000; // 1%

    int24 private constant TICK_SPACING_LOW = 1; // 对应 0.01% 费率
    int24 private constant TICK_SPACING_MEDIUM = 10; // 对应 0.05% 费率
    int24 private constant TICK_SPACING_HIGH = 60; // 对应 0.3% 费率
    int24 private constant TICK_SPACING_VERY_HIGH = 200; // 对应 1% 费率

    /**
     * @notice 交易路径信息
     * @param tokens 交易路径中的代币序列
     * @param fees 每一跳的费用
     * @param isDirectPath 是否为直接路径
     */
    struct SwapPath {
        address[] tokens; // 交易路径中的代币序列
        uint24[] fees; // 每一跳的费用
        bool isDirectPath; // 是否为直接路径
    }

    // Uniswap Universal Router 地址
    UniversalRouter public immutable UNIVERSAL_ROUTER;
    IPermit2 public immutable PERMIT2;
    address public immutable WETH;
    address public immutable USDC;
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

    event EmergencyPaused(address indexed caller, uint256 timestamp);

    event EmergencyUnpaused(address indexed caller, uint256 timestamp);

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "AaveV3FlashLoan: caller is not the owner"
        );
        _;
    }

    constructor(
        address _addressProvider,
        address _universalRouter,
        address _permit2,
        address _weth,
        address _usdc,
        uint256 _builderPaymentPercentage
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
        require(
            _addressProvider != address(0),
            "AaveV3FlashLoan: invalid address provider"
        );
        require(
            _universalRouter != address(0),
            "AaveV3FlashLoan: invalid universal router"
        );
        require(_permit2 != address(0), "AaveV3FlashLoan: invalid permit2");
        require(_weth != address(0), "AaveV3FlashLoan: invalid WETH");
        require(_usdc != address(0), "AaveV3FlashLoan: invalid USDC");
        require(
            _builderPaymentPercentage <= MAX_BUILDER_PAYMENT_PERCENTAGE,
            "AaveV3FlashLoan: invalid builder payment percentage"
        );

        // 获取 Aave Oracle 地址
        ORACLE = IPriceOracleGetter(
            IPoolAddressesProvider(_addressProvider).getPriceOracle()
        );

        owner = msg.sender;
        UNIVERSAL_ROUTER = UniversalRouter(payable(_universalRouter));
        PERMIT2 = IPermit2(_permit2);
        WETH = _weth;
        USDC = _usdc;
        builderPaymentPercentage = _builderPaymentPercentage;
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
            "AaveV3FlashLoan: invalid builder payment percentage"
        );
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
        uint256 deadline, // 交易截止时间
        bool useMaxDebt // 是否使用最大债务清算
    ) external onlyOwner whenNotPaused nonReentrant {
        require(
            collateralAsset != address(0),
            "AaveV3FlashLoan: invalid collateral asset"
        );
        require(debtAsset != address(0), "AaveV3FlashLoan: invalid debt asset");
        require(user != address(0), "AaveV3FlashLoan: invalid user address");
        require(
            collateralAsset != debtAsset,
            "AaveV3FlashLoan: collateral and debt cannot be same asset"
        );
        require(
            deadline > block.timestamp,
            "AaveV3FlashLoan: deadline expired"
        );

        // 提前检查用户的健康值是否小于清算阈值，避免不必要的闪电贷
        (, , , , , uint256 healthFactor) = POOL.getUserAccountData(user);
        require(
            healthFactor < 1e18,
            "AaveV3FlashLoan: user health factor above threshold"
        );

        uint256 actualDebtToCover = debtToCover;

        // 如果使用最大债务清算，获取用户全部债务余额
        // 让 Aave 协议自己决定实际清算数量，我们在后续处理未消耗的余额
        if (useMaxDebt) {
            actualDebtToCover = _getUserDebtBalance(debtAsset, user);
            require(
                actualDebtToCover > 0,
                "AaveV3FlashLoan: user has no debt in this asset"
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
        require(msg.sender == address(POOL), "AaveV3FlashLoan: unauthorized");
        require(
            initiator == address(this),
            "AaveV3FlashLoan: unauthorized initiator"
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
            "AaveV3FlashLoan: deadline expired"
        );

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
        // 记录清算前的债务资产余额
        uint256 debtAssetBalanceBefore = IERC20(asset).balanceOf(address(this));

        // 授权 Aave 使用债务资产
        IERC20(asset).forceApprove(address(POOL), amount + premium);

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
            "AaveV3FlashLoan: no collateral received"
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
            "AaveV3FlashLoan: insufficient debt asset to repay flash loan"
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
        // 安全检查
        require(
            collateralAsset != debtAsset,
            "AaveV3FlashLoan: same asset swap not allowed"
        );

        // 授权 Permit2 使用抵押品
        IERC20(collateralAsset).forceApprove(
            address(PERMIT2),
            collateralBalance
        );

        // 查找最佳交易路径
        SwapPath memory path = _findBestPath(collateralAsset, debtAsset);

        // 构建 V4_SWAP 命令
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // 构建 Actions 序列
        bytes memory actions;
        if (path.isDirectPath) {
            // 直接交易路径
            actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_IN_SINGLE),
                uint8(Actions.SETTLE_ALL),
                uint8(Actions.TAKE_ALL)
            );
        } else {
            // 中转交易路径
            actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_IN),
                uint8(Actions.SETTLE_ALL),
                uint8(Actions.TAKE_ALL)
            );
        }

        // 准备每个 action 的参数
        bytes[] memory params = new bytes[](3);
        if (path.isDirectPath) {
            // 直接交易参数
            PoolKey memory poolKey = _buildPoolKey(
                path.tokens[0],
                path.tokens[1],
                path.fees[0]
            );

            params[0] = abi.encode(
                IV4Router.ExactInputSingleParams({
                    poolKey: poolKey,
                    zeroForOne: _determineZeroForOne(
                        path.tokens[0],
                        path.tokens[1]
                    ),
                    amountIn: uint128(collateralBalance),
                    amountOutMinimum: uint128(requiredDebtAmount),
                    hookData: ""
                })
            );
        } else {
            // 中转交易参数
            params[0] = abi.encode(
                IV4Router.ExactInputParams({
                    currencyIn: Currency.wrap(path.tokens[0]),
                    path: _buildPathKeys(path),
                    amountIn: uint128(collateralBalance),
                    amountOutMinimum: uint128(requiredDebtAmount)
                })
            );
        }

        params[1] = abi.encode(
            Currency.wrap(collateralAsset),
            collateralBalance
        );
        params[2] = abi.encode(Currency.wrap(debtAsset), requiredDebtAmount);

        // 组合 actions 和 params
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // 执行兑换
        uint256 deadline = block.timestamp + 60;
        try UNIVERSAL_ROUTER.execute(commands, inputs, deadline) {
            // 验证兑换是否成功获得足够的债务资产
            uint256 debtAssetBalance = IERC20(debtAsset).balanceOf(
                address(this)
            );
            require(
                debtAssetBalance >= requiredDebtAmount,
                "AaveV3FlashLoan: insufficient debt asset after swap"
            );
        } catch Error(string memory reason) {
            revert(
                string(
                    abi.encodePacked(
                        "AaveV3FlashLoan: V4 swap failed - ",
                        reason
                    )
                )
            );
        } catch {
            revert("AaveV3FlashLoan: V4 swap failed with unknown error");
        }
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
                IERC20(asset).forceApprove(
                    address(PERMIT2),
                    remainingDebtAsset
                );

                // 查找最佳交易路径
                SwapPath memory path = _findBestPath(asset, WETH);

                // 获取价格和精度信息用于计算最小输出金额
                uint256 inputPrice = ORACLE.getAssetPrice(asset);
                uint256 outputPrice = ORACLE.getAssetPrice(WETH);
                uint256 inputDecimals = IERC20Metadata(asset).decimals();
                uint256 outputDecimals = IERC20Metadata(WETH).decimals();

                require(
                    inputPrice > 0,
                    "AaveV3FlashLoan: invalid input token price"
                );
                require(
                    outputPrice > 0,
                    "AaveV3FlashLoan: invalid output token price"
                );

                // 计算理论上的输出金额（不考虑滑点）
                uint256 theoreticalAmountOut = (remainingDebtAsset *
                    inputPrice *
                    (10 ** outputDecimals)) /
                    (outputPrice * (10 ** inputDecimals));

                // 应用 5% 的滑点保护
                uint256 minWethOut = (theoreticalAmountOut * 95) / 100;

                // 构建 V4_SWAP 命令
                bytes memory commands = abi.encodePacked(
                    uint8(Commands.V4_SWAP)
                );

                // 构建 Actions 序列
                bytes memory actions;
                if (path.isDirectPath) {
                    // 直接交易路径
                    actions = abi.encodePacked(
                        uint8(Actions.SWAP_EXACT_IN_SINGLE),
                        uint8(Actions.SETTLE_ALL),
                        uint8(Actions.TAKE_ALL)
                    );
                } else {
                    // 中转交易路径
                    actions = abi.encodePacked(
                        uint8(Actions.SWAP_EXACT_IN),
                        uint8(Actions.SETTLE_ALL),
                        uint8(Actions.TAKE_ALL)
                    );
                }

                // 准备每个 action 的参数
                bytes[] memory params = new bytes[](3);
                if (path.isDirectPath) {
                    // 直接交易参数
                    PoolKey memory poolKey = _buildPoolKey(
                        path.tokens[0],
                        path.tokens[1],
                        path.fees[0]
                    );

                    params[0] = abi.encode(
                        IV4Router.ExactInputSingleParams({
                            poolKey: poolKey,
                            zeroForOne: _determineZeroForOne(
                                path.tokens[0],
                                path.tokens[1]
                            ),
                            amountIn: uint128(remainingDebtAsset),
                            amountOutMinimum: uint128(minWethOut),
                            hookData: ""
                        })
                    );
                } else {
                    // 中转交易参数
                    params[0] = abi.encode(
                        IV4Router.ExactInputParams({
                            currencyIn: Currency.wrap(path.tokens[0]),
                            path: _buildPathKeys(path),
                            amountIn: uint128(remainingDebtAsset),
                            amountOutMinimum: uint128(minWethOut)
                        })
                    );
                }

                params[1] = abi.encode(
                    Currency.wrap(asset),
                    remainingDebtAsset
                );
                params[2] = abi.encode(Currency.wrap(WETH), minWethOut);

                // 组合 actions 和 params
                bytes[] memory inputs = new bytes[](1);
                inputs[0] = abi.encode(actions, params);

                // 执行兑换
                uint256 deadline = block.timestamp + 60;
                try UNIVERSAL_ROUTER.execute(commands, inputs, deadline) {
                    // 验证兑换是否成功
                    uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
                    require(
                        wethBalance >= minWethOut,
                        "AaveV3FlashLoan: insufficient WETH received"
                    );

                    // 将 WETH 转换成 ETH
                    IWETH(WETH).withdraw(wethBalance);
                } catch Error(string memory reason) {
                    revert(
                        string(
                            abi.encodePacked(
                                "AaveV3FlashLoan: V4 WETH swap failed - ",
                                reason
                            )
                        )
                    );
                } catch {
                    revert(
                        "AaveV3FlashLoan: V4 WETH swap failed with unknown error"
                    );
                }
            }

            // 计算从兑换中获得的 ETH（只计算新增的 ETH）
            uint256 ethBalanceAfter = address(this).balance;
            uint256 profitEth = ethBalanceAfter - ethBalanceBefore;

            if (profitEth > 0) {
                uint256 builderPayment = (profitEth *
                    builderPaymentPercentage) / 100;

                if (builderPayment > 0) {
                    // 支付给 Builder
                    (bool success, ) = block.coinbase.call{
                        value: builderPayment
                    }(new bytes(0));
                    if (!success) {
                        emit BuilderPaymentFailed(
                            block.coinbase,
                            builderPayment,
                            "Builder payment failed"
                        );
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
     * @notice 获取最优费用层级的池子
     * @param inputToken 输入代币地址
     * @param outputToken 输出代币地址
     * @return fee 最优费用层级
     * @dev 通过检查不同费用层级的流动性来找到最优的池子
     */
    function _getBestPool(
        address inputToken,
        address outputToken
    ) private view returns (uint24) {
        // 定义常用的费用层级（按流动性从高到低排序）
        uint24[] memory feeTiers = new uint24[](3);
        feeTiers[0] = FEE_MEDIUM;    // 0.05% - 稳定币对
        feeTiers[1] = FEE_HIGH;      // 0.3%  - 主流代币对
        feeTiers[2] = FEE_VERY_HIGH; // 1%    - 波动性较大的代币对

        uint256 bestLiquidity = 0;
        uint24 bestFee = 0; // 初始化为 0，表示没有找到有效的交易池

        // 遍历所有费用层级，找到流动最大的池子
        for (uint256 i = 0; i < feeTiers.length; i++) {
            try
                this.getPoolLiquidity(inputToken, outputToken, feeTiers[i])
            returns (uint256 liquidity) {
                if (liquidity > bestLiquidity) {
                    bestLiquidity = liquidity;
                    bestFee = feeTiers[i];
                }
            } catch {
                // 如果获取流动性和失败，说明费用层级的池子不存在或流动性不足，继续尝试下一个
                continue;
            }
        }

        return bestFee; // 如果没有找到有效的交易池，返回 0
    }

    /**
     * @notice 获取指定池子的流动性
     * @param inputToken 输入代币地址
     * @param outputToken 输出代币地址
     * @param fee 费用层级
     * @return liquidity 池子的流动性
     * @dev 这个函数是 external 的，因为我们需要在 try-catch 中调用它
     */
    function getPoolLiquidity(
        address inputToken,
        address outputToken,
        uint24 fee
    ) external view returns (uint256 liquidity) {
        // 构建 PoolKey
        PoolKey memory poolKey = _buildPoolKey(inputToken, outputToken, fee);

        // 使用 StateLibrary 获取池子流动性
        return
            uint256(
                UNIVERSAL_ROUTER.poolManager().getLiquidity(poolKey.toId())
            );
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
        require(token != address(0), "AaveV3FlashLoan: invalid token address");
        require(amount > 0, "AaveV3FlashLoan: invalid amount");

        IERC20(token).safeTransfer(owner, amount);
        emit TokensWithdrawn(token, owner, amount, block.timestamp);
    }

    /**
     * @notice 提取合约中的 ETH
     * @param amount 要提取的数量，如果为 0 或大于余额则提取全部
     */
    function withdrawETH(uint256 amount) external onlyOwner whenNotPaused {
        uint256 balance = address(this).balance;
        require(balance > 0, "AaveV3FlashLoan: no ETH to withdraw");

        uint256 withdrawAmount;
        if (amount == 0 || amount >= balance) {
            withdrawAmount = balance;
        } else {
            withdrawAmount = amount;
        }

        (bool success, ) = owner.call{value: withdrawAmount}("");
        require(success, "AaveV3FlashLoan: ETH transfer failed");

        emit TokensWithdrawn(
            address(0),
            owner,
            withdrawAmount,
            block.timestamp
        );
    }

    /**
     * @notice 根据费率获取对应的 tickSpacing
     * @param fee 费率
     * @return tickSpacing 对应的 tickSpacing 值
     */
    function _getTickSpacingByFee(uint24 fee) private pure returns (int24) {
        if (fee == FEE_LOW) return TICK_SPACING_LOW;
        if (fee == FEE_MEDIUM) return TICK_SPACING_MEDIUM;
        if (fee == FEE_HIGH) return TICK_SPACING_HIGH;
        if (fee == FEE_VERY_HIGH) return TICK_SPACING_VERY_HIGH;
        revert("AaveV3FlashLoan: invalid fee tier");
    }

    /**
     * @notice 构建 Uniswap V4 PoolKey
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @param fee 费用层级
     * @return poolKey 构建好的 PoolKey，currency0 < currency1（协议要求）
     * @dev PoolKey 必须确保 currency0 < currency1，这是 Uniswap V4 协议的强制要求，
     *      用于确保每个代币对只有一个唯一的池子标识符
     */
    function _buildPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private pure returns (PoolKey memory) {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        return
            PoolKey({
                currency0: Currency.wrap(token0),
                currency1: Currency.wrap(token1),
                fee: fee,
                tickSpacing: _getTickSpacingByFee(fee),
                hooks: IHooks(address(0)) // 使用标准池，无自定义 hooks
            });
    }

    /**
     * @notice 确定 Uniswap V4 交换方向
     * @param inputToken 输入代币地址
     * @param outputToken 输出代币地址
     * @return 如果从 currency0 换到 currency1 返回 true，否则返回 false
     * @dev 这个函数的职责与 _buildPoolKey 不同：
     *      - _buildPoolKey: 确保池子标识符的唯一性（currency0 < currency1）
     *      - _determineZeroForOne: 确保正确的交换方向（inputToken -> outputToken）
     *      两者协同工作，确保无论代币地址大小如何，都能正确执行期望的交换
     */
    function _determineZeroForOne(
        address inputToken,
        address outputToken
    ) private pure returns (bool) {
        return uint160(inputToken) < uint160(outputToken);
    }

    /**
     * @notice 构建 Uniswap V4 多跳交易的路径键数组
     * @param path 交易路径信息
     * @return pathKeys 路径键数组
     * @dev 根据交易路径中的代币序列和费用序列构建 PathKey 数组
     */
    function _buildPathKeys(
        SwapPath memory path
    ) private pure returns (PathKey[] memory) {
        // 缓存数组长度以节省 gas
        uint256 tokensLength = path.tokens.length;
        uint256 feesLength = path.fees.length;

        require(tokensLength >= 2, "AaveV3FlashLoan: invalid path length");
        require(
            tokensLength == feesLength + 1,
            "AaveV3FlashLoan: tokens and fees length mismatch"
        );

        // 使用 unchecked 进行减法操作，因为我们已经验证了 tokensLength >= 2
        uint256 pathLength;
        unchecked {
            pathLength = tokensLength - 1;
        }

        PathKey[] memory pathKeys = new PathKey[](pathLength);
        IHooks emptyHooks = IHooks(address(0));

        // 缓存常用值以减少存储读取
        address[] memory tokens = path.tokens;
        uint24[] memory fees = path.fees;

        for (uint256 i = 0; i < pathLength; ) {
            // 缓存下一个代币地址
            address nextToken;
            unchecked {
                nextToken = tokens[i + 1];
            }

            pathKeys[i] = PathKey({
                intermediateCurrency: Currency.wrap(nextToken),
                fee: fees[i],
                tickSpacing: _getTickSpacingByFee(fees[i]),
                hooks: emptyHooks,
                hookData: ""
            });

            // 使用 unchecked 递增计数器
            unchecked {
                ++i;
            }
        }

        return pathKeys;
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

    /**
     * @notice 查找最佳交易路径
     * @param tokenIn 输入代币地址
     * @param tokenOut 输出代币地址
     * @return path 最佳交易路径，包含代币序列、费用序列和是否为直接路径
     * @dev 按以下顺序尝试查找路径：
     *      1. 直接交易路径
     *      2. 通过 USDC 中转
     *      3. 通过 WETH 中转
     */
    function _findBestPath(
        address tokenIn,
        address tokenOut
    ) private view returns (SwapPath memory path) {
        // 检查直接交易池
        uint24 directFee = _getBestPool(tokenIn, tokenOut);
        if (directFee > 0) {
            path.tokens = new address[](2);
            path.tokens[0] = tokenIn;
            path.tokens[1] = tokenOut;
            path.fees = new uint24[](1);
            path.fees[0] = directFee;
            path.isDirectPath = true;
            return path;
        }

        // 尝试通过 USDC 中转
        uint24 inToUsdcFee = _getBestPool(tokenIn, USDC);
        uint24 usdcToOutFee = _getBestPool(USDC, tokenOut);
        if (inToUsdcFee > 0 && usdcToOutFee > 0) {
            path.tokens = new address[](3);
            path.tokens[0] = tokenIn;
            path.tokens[1] = USDC;
            path.tokens[2] = tokenOut;
            path.fees = new uint24[](2);
            path.fees[0] = inToUsdcFee;
            path.fees[1] = usdcToOutFee;
            path.isDirectPath = false;
            return path;
        }

        // 尝试通过 WETH 中转
        uint24 inToWethFee = _getBestPool(tokenIn, WETH);
        uint24 wethToOutFee = _getBestPool(WETH, tokenOut);
        if (inToWethFee > 0 && wethToOutFee > 0) {
            path.tokens = new address[](3);
            path.tokens[0] = tokenIn;
            path.tokens[1] = WETH;
            path.tokens[2] = tokenOut;
            path.fees = new uint24[](2);
            path.fees[0] = inToWethFee;
            path.fees[1] = wethToOutFee;
            path.isDirectPath = false;
            return path;
        }

        revert("AaveV3FlashLoan: no valid swap path found");
    }
}
