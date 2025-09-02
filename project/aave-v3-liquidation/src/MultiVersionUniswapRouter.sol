// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20, IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

// Uniswap Universal Router imports
import {UniversalRouter} from '@uniswap/universal-router/contracts/UniversalRouter.sol';
import {Commands} from '@uniswap/universal-router/contracts/libraries/Commands.sol';
import {IPermit2} from '@uniswap/permit2/src/interfaces/IPermit2.sol';

// Uniswap V4 imports
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';
import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';
import {StateLibrary} from '@uniswap/v4-core/src/libraries/StateLibrary.sol';
import {PoolId, PoolIdLibrary} from '@uniswap/v4-core/src/types/PoolId.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {PathKey} from '@uniswap/v4-periphery/src/libraries/PathKey.sol';

// V2 接口定义（用于流动性检查）
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

// V3 接口定义（用于流动性检查）
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
    function liquidity() external view returns (uint128);
}

// V4 相关接口定义
interface IV4Router {
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    struct ExactInputParams {
        Currency currencyIn;
        PathKey[] path;
        uint128 amountIn;
        uint128 amountOutMinimum;
    }
}


/**
 * @title MultiVersionUniswapRouter
 * @author 
 * @notice 支持多版本 Uniswap (V2, V3, V4) 的智能路由器，统一使用 Universal Router
 * @dev 该合约通过比较不同版本池子的流动性，自动选择最优路径进行代币交换
 *      所有交换都通过 Uniswap Universal Router 执行，支持：
 *      1. 自动检测 V2、V3、V4 版本的池子流动性
 *      2. 选择流动性最好的版本进行交换
 *      3. 支持直接交换和多跳交换
 *      4. 提供统一的接口供外部合约调用
 */
contract MultiVersionUniswapRouter is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Accept any ETH refunds from Universal Router (e.g., leftover native currency)
    receive() external payable {}
    fallback() external payable {}

    // 版本枚举
    enum UniswapVersion {
        V2,
        V3,
        V4
    }

    // 交换路径信息
    struct SwapPath {
        address[] tokens;           // 交易路径中的代币序列
        uint24[] fees;             // V3/V4 每一跳的费用
        bool isDirectPath;         // 是否为直接路径
        UniswapVersion version;    // 使用的 Uniswap 版本
        uint256 expectedLiquidity; // 预期流动性
    }

    // 流动性信息
    struct LiquidityInfo {
        UniswapVersion version;
        uint256 liquidity;
        uint24 fee;  // 仅 V3/V4 使用
        bool exists;
    }

    // 常量定义
    uint24 private constant FEE_LOW = 100;      // 0.01%
    uint24 private constant FEE_MEDIUM = 500;   // 0.05%
    uint24 private constant FEE_HIGH = 3000;    // 0.3%
    uint24 private constant FEE_VERY_HIGH = 10000; // 1%

    int24 private constant TICK_SPACING_LOW = 1;
    int24 private constant TICK_SPACING_MEDIUM = 10;
    int24 private constant TICK_SPACING_HIGH = 60;
    int24 private constant TICK_SPACING_VERY_HIGH = 200;

    // 合约地址
    UniversalRouter public immutable UNIVERSAL_ROUTER;
    IPermit2 public immutable PERMIT2;
    IUniswapV2Factory public immutable V2_FACTORY;
    IUniswapV3Factory public immutable V3_FACTORY;
    IPoolManager public immutable POOL_MANAGER;  // V4 PoolManager

    address public immutable WETH;
    address public immutable USDC;

    // 事件
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        UniswapVersion version,
        address indexed recipient
    );

    event BestPathFound(
        address indexed tokenIn,
        address indexed tokenOut,
        UniswapVersion version,
        uint256 liquidity,
        bool isDirectPath
    );

    constructor(
        address _universalRouter,
        address _permit2,
        address _v2Factory,
        address _v3Factory,
        address _poolManager,
        address _weth,
        address _usdc
    ) Ownable(msg.sender) {
        UNIVERSAL_ROUTER = UniversalRouter(payable(_universalRouter));
        PERMIT2 = IPermit2(_permit2);
        V2_FACTORY = IUniswapV2Factory(_v2Factory);
        V3_FACTORY = IUniswapV3Factory(_v3Factory);
        POOL_MANAGER = IPoolManager(_poolManager);

        WETH = _weth;
        USDC = _usdc;

    }

    /**
     * @notice 执行代币交换，自动选择最优版本
     * @param tokenIn 输入代币地址
     * @param tokenOut 输出代币地址
     * @param amountIn 输入数量
     * @param amountOutMinimum 最小输出数量
     * @param recipient 接收者地址
     * @return amountOut 实际输出数量
     */
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) external nonReentrant returns (uint256 amountOut) {
        require(tokenIn != tokenOut, 'MultiVersionRouter: same token swap');
        require(amountIn > 0, 'MultiVersionRouter: invalid amount');
        require(recipient != address(0), 'MultiVersionRouter: invalid recipient');
        
        // 检查用户余额，避免授权但余额不足时浪费 gas
        uint256 userBalance = IERC20(tokenIn).balanceOf(msg.sender);
        require(userBalance >= amountIn, 'MultiVersionRouter: insufficient balance');

        // 将代币预先转入 Universal Router，使用 payerIsUser=false 由 Universal Router 自有余额支付
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(UNIVERSAL_ROUTER), amountIn);

        // 查找最佳交换路径
        SwapPath memory bestPath = findBestSwapPath(tokenIn, tokenOut);

        // 记录交换前的余额
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient);

        // 根据版本执行交换（V2/V3 设置 payerIsUser=false，使用 Universal Router 自身余额）
        if (bestPath.version == UniswapVersion.V2) {
            _swapV2Universal(bestPath, amountIn, amountOutMinimum, recipient);
        } else if (bestPath.version == UniswapVersion.V3) {
            _swapV3Universal(bestPath, amountIn, amountOutMinimum, recipient);
        } else if (bestPath.version == UniswapVersion.V4) {
            _swapV4Universal(bestPath, amountIn, amountOutMinimum, recipient);
        } else {
            revert('MultiVersionRouter: no valid swap path found');
        }

        // 计算实际输出数量
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(recipient);
        amountOut = balanceAfter - balanceBefore;

        require(amountOut >= amountOutMinimum, 'MultiVersionRouter: insufficient output amount');

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, bestPath.version, recipient);
    }

    /**
     * @notice 查找最佳交换路径
     * @param tokenIn 输入代币地址
     * @param tokenOut 输出代币地址
     * @return bestPath 最佳交换路径
     */
    function findBestSwapPath(
        address tokenIn,
        address tokenOut
    ) public returns (SwapPath memory bestPath) {
        uint256 bestLiquidity = 0;
        bool foundPath = false;

        // 检查直接路径
        LiquidityInfo[] memory directPaths = _getDirectPathLiquidity(tokenIn, tokenOut);
        for (uint256 i = 0; i < directPaths.length; i++) {
            if (directPaths[i].exists && directPaths[i].liquidity > bestLiquidity) {
                bestLiquidity = directPaths[i].liquidity;
                bestPath = SwapPath({
                    tokens: _createTokenArray(tokenIn, tokenOut),
                    fees: directPaths[i].version == UniswapVersion.V2 ? new uint24[](0) : _createFeeArray(directPaths[i].fee),
                    isDirectPath: true,
                    version: directPaths[i].version,
                    expectedLiquidity: directPaths[i].liquidity
                });
                foundPath = true;
            }
        }

        // 如果找到直接路径，直接返回，不再搜索中转路径
        if (foundPath) {
            emit BestPathFound(tokenIn, tokenOut, bestPath.version, bestPath.expectedLiquidity, bestPath.isDirectPath);
            return bestPath;
        }

        // 检查通过 USDC 中转的路径
        if (tokenIn != USDC && tokenOut != USDC) {
            LiquidityInfo[] memory usdcPath1 = _getDirectPathLiquidity(tokenIn, USDC);
            LiquidityInfo[] memory usdcPath2 = _getDirectPathLiquidity(USDC, tokenOut);
            
            for (uint256 i = 0; i < usdcPath1.length; i++) {
                for (uint256 j = 0; j < usdcPath2.length; j++) {
                    if (usdcPath1[i].exists && usdcPath2[j].exists) {
                        // 使用较小的流动性作为路径流动性
                        uint256 pathLiquidity = usdcPath1[i].liquidity < usdcPath2[j].liquidity 
                            ? usdcPath1[i].liquidity : usdcPath2[j].liquidity;
                        
                        if (pathLiquidity > bestLiquidity) {
                            bestLiquidity = pathLiquidity;
                            // 只有相同版本的路径才能组合成单一路径
                            if (usdcPath1[i].version == usdcPath2[j].version) {
                                bestPath = SwapPath({
                                    tokens: _createTokenArray(tokenIn, USDC, tokenOut),
                                    fees: usdcPath1[i].version == UniswapVersion.V2 ? new uint24[](0) : _createFeeArray(usdcPath1[i].fee, usdcPath2[j].fee),
                                    isDirectPath: false,
                                    version: usdcPath1[i].version,
                                    expectedLiquidity: pathLiquidity
                                });
                                foundPath = true;
                            }
                            // 跨版本路径需要拆分执行，暂时跳过（需要实现多段执行逻辑）
                        }
                    }
                }
            }
        }

        // 检查通过 WETH 中转的路径
        if (tokenIn != WETH && tokenOut != WETH) {
            LiquidityInfo[] memory wethPath1 = _getDirectPathLiquidity(tokenIn, WETH);
            LiquidityInfo[] memory wethPath2 = _getDirectPathLiquidity(WETH, tokenOut);
            
            for (uint256 i = 0; i < wethPath1.length; i++) {
                for (uint256 j = 0; j < wethPath2.length; j++) {
                    if (wethPath1[i].exists && wethPath2[j].exists) {
                        uint256 pathLiquidity = wethPath1[i].liquidity < wethPath2[j].liquidity 
                            ? wethPath1[i].liquidity : wethPath2[j].liquidity;
                        
                        if (pathLiquidity > bestLiquidity) {
                            bestLiquidity = pathLiquidity;
                            // 只有相同版本的路径才能组合成单一路径
                            if (wethPath1[i].version == wethPath2[j].version) {
                                bestPath = SwapPath({
                                    tokens: _createTokenArray(tokenIn, WETH, tokenOut),
                                    fees: wethPath1[i].version == UniswapVersion.V2 ? new uint24[](0) : _createFeeArray(wethPath1[i].fee, wethPath2[j].fee),
                                    isDirectPath: false,
                                    version: wethPath1[i].version,
                                    expectedLiquidity: pathLiquidity
                                });
                                foundPath = true;
                            }
                            // 跨版本路径需要拆分执行，暂时跳过（需要实现多段执行逻辑）
                        }
                    }
                }
            }
        }

        require(foundPath, 'MultiVersionRouter: no valid swap path found');
        
        emit BestPathFound(tokenIn, tokenOut, bestPath.version, bestPath.expectedLiquidity, bestPath.isDirectPath);
    }

    /**
     * @notice 通过 Universal Router 执行 V2 交换
     */
    function _swapV2Universal(
        SwapPath memory path,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) private {
        // 构建 V2_SWAP 命令
        bytes memory commands = abi.encodePacked(uint8(Commands.V2_SWAP_EXACT_IN));
        
        // 构建输入参数
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            recipient,
            amountIn,
            amountOutMinimum,
            path.tokens,
            false // payerIsUser: 资金来源为 Universal Router 自身余额（本合约已预转入）
        );

        // 执行交换
        uint256 deadline = block.timestamp + 300;
        UNIVERSAL_ROUTER.execute(commands, inputs, deadline);
    }

    /**
     * @notice 通过 Universal Router 执行 V3 交换
     */
    function _swapV3Universal(
        SwapPath memory path,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) private {
        bytes memory commands;
        bytes[] memory inputs = new bytes[](1);

        // 使用 V3_SWAP_EXACT_IN
        commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
        inputs[0] = abi.encode(
            recipient,
            amountIn,
            amountOutMinimum,
            _encodeV3Path(path.tokens, path.fees),
            false // payerIsUser: 资金来源为 Universal Router 自身余额（本合约已预转入）
        );

        // 执行交换
        uint256 deadline = block.timestamp + 300;
        UNIVERSAL_ROUTER.execute(commands, inputs, deadline);
    }

    /**
     * @notice 通过 Universal Router 执行 V4 交换
     */
    function _swapV4Universal(
        SwapPath memory path,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) private {
        // 构建 V4_SWAP 命令
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // 构建 Actions 序列
        bytes memory actions;
        if (path.isDirectPath) {
            // 直接交易路径
            actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_IN_SINGLE),
                uint8(Actions.SETTLE),
                uint8(Actions.TAKE)
            );
        } else {
            // 中转交易路径
            actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_IN),
                uint8(Actions.SETTLE),
                uint8(Actions.TAKE)
            );
        }

        // 准备每个 action 的参数
        bytes[] memory params = new bytes[](3);
        if (path.isDirectPath) {
            // 直接交易参数
            PoolKey memory poolKey = _buildV4PoolKey(
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
                    amountIn: uint128(amountIn),
                    amountOutMinimum: uint128(amountOutMinimum),
                    hookData: ''
                })
            );
        } else {
            // 中转交易参数
            params[0] = abi.encode(
                IV4Router.ExactInputParams({
                    currencyIn: Currency.wrap(path.tokens[0]),
                    path: _buildV4PathKeys(path),
                    amountIn: uint128(amountIn),
                    amountOutMinimum: uint128(amountOutMinimum)
                })
            );
        }

        params[1] = abi.encode(
            Currency.wrap(path.tokens[0]),
            amountIn,
            false // payerIsUser = false，使用 Universal Router 的余额
        );
        params[2] = abi.encode(Currency.wrap(path.tokens[path.tokens.length - 1]), recipient, uint128(0)); // 使用 OPEN_DELTA

        // 组合 actions 和 params
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // 执行兑换
        uint256 deadline = block.timestamp + 300;
        UNIVERSAL_ROUTER.execute(commands, inputs, deadline);
    }

    /**
     * @notice 编码 V3 路径
     */
    function _encodeV3Path(
        address[] memory tokens,
        uint24[] memory fees
    ) private pure returns (bytes memory path) {
        path = abi.encodePacked(tokens[0]);
        for (uint256 i = 0; i < fees.length; i++) {
            path = abi.encodePacked(path, fees[i], tokens[i + 1]);
        }
    }

    /**
     * @notice 构建 V4 路径键
     */
    function _buildV4PathKeys(
        SwapPath memory path
    ) private pure returns (PathKey[] memory pathKeys) {
        require(path.tokens.length >= 3, 'MultiVersionRouter: invalid path length');
        
        pathKeys = new PathKey[](path.tokens.length - 2);
        for (uint256 i = 0; i < pathKeys.length; i++) {
            pathKeys[i] = PathKey({
                intermediateCurrency: Currency.wrap(path.tokens[i + 1]),
                fee: path.fees[i],
                tickSpacing: _getTickSpacingByFee(path.fees[i]),
                hooks: IHooks(address(0)),
                hookData: ''
            });
        }
    }

    /**
     * @notice 确定 V4 交换方向
     */
    function _determineZeroForOne(
        address tokenA,
        address tokenB
    ) private pure returns (bool) {
        return tokenA < tokenB;
    }

    /**
     * @notice 获取直接路径的流动性信息
     */
    function _getDirectPathLiquidity(
        address tokenA,
        address tokenB
    ) private view returns (LiquidityInfo[] memory liquidityInfos) {
        liquidityInfos = new LiquidityInfo[](7); // V2(1) + V3(3) + V4(3)
        uint256 index = 0;

        // 检查 V2 流动性
        liquidityInfos[index] = _getV2Liquidity(tokenA, tokenB);
        index++;

        // 检查 V3 流动性（多个费率层级）
        uint24[] memory v3Fees = new uint24[](3);
        v3Fees[0] = FEE_MEDIUM;
        v3Fees[1] = FEE_HIGH;
        v3Fees[2] = FEE_LOW;
        
        for (uint256 i = 0; i < v3Fees.length; i++) {
            liquidityInfos[index] = _getV3Liquidity(tokenA, tokenB, v3Fees[i]);
            index++;
        }

        // 检查 V4 流动性（多个费率层级）
        uint24[] memory v4Fees = new uint24[](3);
        v4Fees[0] = FEE_MEDIUM;
        v4Fees[1] = FEE_HIGH;
        v4Fees[2] = FEE_LOW;
        
        for (uint256 i = 0; i < v4Fees.length; i++) {
            liquidityInfos[index] = _getV4Liquidity(tokenA, tokenB, v4Fees[i]);
            index++;
        }
    }

    /**
     * @notice 获取 V2 池子流动性
     */
    function _getV2Liquidity(
        address tokenA,
        address tokenB
    ) private view returns (LiquidityInfo memory) {
        address pair = V2_FACTORY.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            return LiquidityInfo({
                version: UniswapVersion.V2,
                liquidity: 0,
                fee: 0,
                exists: false
            });
        }

        try IUniswapV2Pair(pair).getReserves() returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32
        ) {
            if (reserve0 == 0 || reserve1 == 0) {
                return LiquidityInfo({
                    version: UniswapVersion.V2,
                    liquidity: 0,
                    fee: 0,
                    exists: false
                });
            }
            
            // 直接使用储备量的几何平均数作为流动性指标
            uint256 liquidity = _sqrt(uint256(reserve0) * uint256(reserve1));
            return LiquidityInfo({
                version: UniswapVersion.V2,
                liquidity: liquidity,
                fee: 0, // V2 固定费率 0.3%
                exists: liquidity > 0
            });
        } catch {
            return LiquidityInfo({
                version: UniswapVersion.V2,
                liquidity: 0,
                fee: 0,
                exists: false
            });
        }
    }

    /**
     * @notice 获取 V3 池子流动性
     */
    function _getV3Liquidity(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (LiquidityInfo memory) {
        address pool = V3_FACTORY.getPool(tokenA, tokenB, fee);
        if (pool == address(0)) {
            return LiquidityInfo({
                version: UniswapVersion.V3,
                liquidity: 0,
                fee: fee,
                exists: false
            });
        }

        try IUniswapV3Pool(pool).liquidity() returns (uint128 liquidity) {
            return LiquidityInfo({
                version: UniswapVersion.V3,
                liquidity: uint256(liquidity),
                fee: fee,
                exists: liquidity > 0
            });
        } catch {
            return LiquidityInfo({
                version: UniswapVersion.V3,
                liquidity: 0,
                fee: fee,
                exists: false
            });
        }
    }

    /**
     * @notice 获取 V4 池子流动性
     */
    function _getV4Liquidity(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (LiquidityInfo memory) {
        try this.getV4PoolLiquidity(tokenA, tokenB, fee) returns (uint256 liquidity) {
            return LiquidityInfo({
                version: UniswapVersion.V4,
                liquidity: liquidity,
                fee: fee,
                exists: liquidity > 0
            });
        } catch {
            return LiquidityInfo({
                version: UniswapVersion.V4,
                liquidity: 0,
                fee: fee,
                exists: false
            });
        }
    }

    /**
     * @notice 获取 V4 池子流动性（外部调用以支持 try-catch）
     */
    function getV4PoolLiquidity(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (uint256 liquidity) {
        PoolKey memory poolKey = _buildV4PoolKey(tokenA, tokenB, fee);
        return uint256(POOL_MANAGER.getLiquidity(poolKey.toId()));
    }

    /**
     * @notice 构建 V4 PoolKey
     */
    function _buildV4PoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private pure returns (PoolKey memory) {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: _getTickSpacingByFee(fee),
            hooks: IHooks(address(0))
        });
    }

    /**
     * @notice 根据费率获取 tick spacing
     */
    function _getTickSpacingByFee(uint24 fee) private pure returns (int24) {
        if (fee == FEE_LOW) return TICK_SPACING_LOW;
        if (fee == FEE_MEDIUM) return TICK_SPACING_MEDIUM;
        if (fee == FEE_HIGH) return TICK_SPACING_HIGH;
        if (fee == FEE_VERY_HIGH) return TICK_SPACING_VERY_HIGH;
        revert('MultiVersionRouter: invalid fee tier');
    }

    /**
     * @notice 计算平方根
     */
    function _sqrt(uint256 x) private pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    // 辅助函数：创建代币数组
    function _createTokenArray(address token1, address token2) private pure returns (address[] memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = token1;
        tokens[1] = token2;
        return tokens;
    }

    function _createTokenArray(address token1, address token2, address token3) private pure returns (address[] memory) {
        address[] memory tokens = new address[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = token3;
        return tokens;
    }

    // 辅助函数：创建费用数组
    function _createFeeArray(uint24 fee) private pure returns (uint24[] memory) {
        uint24[] memory fees = new uint24[](1);
        fees[0] = fee;
        return fees;
    }

    function _createFeeArray(uint24 fee1, uint24 fee2) private pure returns (uint24[] memory) {
        uint24[] memory fees = new uint24[](2);
        fees[0] = fee1;
        fees[1] = fee2;
        return fees;
    }

    }