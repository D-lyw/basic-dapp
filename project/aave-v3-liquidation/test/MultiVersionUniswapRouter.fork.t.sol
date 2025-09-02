// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console2} from 'forge-std/Test.sol';
import {MultiVersionUniswapRouter} from '../src/MultiVersionUniswapRouter.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IPermit2} from '@uniswap/permit2/src/interfaces/IPermit2.sol';
import {MockERC20} from 'solmate/src/test/utils/mocks/MockERC20.sol';

// V2 接口
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

// V3 接口
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
    function liquidity() external view returns (uint128);
}

/**
 * @title MultiVersionUniswapRouter Fork Test
 * @notice 使用 Base mainnet fork 测试多版本 Uniswap 路由器
 * @dev 这个测试文件使用真实的 Base 链数据和合约地址
 */
contract MultiVersionUniswapRouterForkTest is Test {
    MultiVersionUniswapRouter public router;
    
    // Base Mainnet 合约地址
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address constant V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant V4_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    
    // 工厂合约接口
    IUniswapV2Factory public V2_FACTORY_INTERFACE;
    IUniswapV3Factory public V3_FACTORY_INTERFACE; 
    
    // Base 链上的主要代币地址
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    address constant CBETH = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;
    address constant WSTETH = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
    
    // 测试用户
    address public testUser;
    
    // 测试参数
    uint256 constant FORK_BLOCK_NUMBER = 34962369; // 使用较新的区块
    uint256 constant TEST_AMOUNT = 1000 * 1e6; // 1000 USDC
    uint256 constant MIN_OUTPUT_AMOUNT = 1; // 最小输出量
    
    function setUp() public {
        // 创建 Base mainnet fork
        vm.createFork(vm.envString('BASE_MAINNET_RPC_URL'), FORK_BLOCK_NUMBER);
        vm.selectFork(0);
        
        // 初始化工厂接口
        V2_FACTORY_INTERFACE = IUniswapV2Factory(V2_FACTORY);
        V3_FACTORY_INTERFACE = IUniswapV3Factory(V3_FACTORY);
        
        // 部署路由器合约
        router = new MultiVersionUniswapRouter(
            UNIVERSAL_ROUTER,
            PERMIT2,
            V2_FACTORY,
            V3_FACTORY,
            V4_POOL_MANAGER,
            WETH,
            USDC
        );
        
        // 给 Universal Router 预置少量原生 ETH，避免部分路径内部需要极少量 ETH 导致 OutOfFunds
        vm.deal(UNIVERSAL_ROUTER, 1 ether);
        
        // 创建测试用户
        testUser = makeAddr('testUser');
        
        console2.log('MultiVersionUniswapRouter deployed at:', address(router));
        console2.log('Test user:', testUser);
    }
    
    /**
     * @notice 测试合约部署配置
     */
    function test_DeployedContractConfig() public view {
        assertEq(address(router.UNIVERSAL_ROUTER()), UNIVERSAL_ROUTER);
        assertEq(address(router.PERMIT2()), PERMIT2);
        assertEq(address(router.V2_FACTORY()), V2_FACTORY);
        assertEq(address(router.V3_FACTORY()), V3_FACTORY);
        assertEq(router.WETH(), WETH);
        assertEq(router.USDC(), USDC);
        
        console2.log('Contract configuration verified');
    }
    
    /**
     * @notice 测试 USDC -> WETH 交换（最常见的交易对）
     */
    function test_SwapUSDCToWETH() public {
        // 给测试用户一些 USDC
        deal(USDC, testUser, TEST_AMOUNT);
        
        vm.startPrank(testUser);
        
        // 检查初始余额
        uint256 initialUSDC = IERC20(USDC).balanceOf(testUser);
        uint256 initialWETH = IERC20(WETH).balanceOf(testUser);
        
        console2.log('Initial USDC balance:', initialUSDC);
        console2.log('Initial WETH balance:', initialWETH);

        IERC20(USDC).approve(address(router), TEST_AMOUNT);
        
        // 执行交换
        uint256 amountOut = router.swapExactTokensForTokens(
            USDC,
            WETH,
            TEST_AMOUNT,
            MIN_OUTPUT_AMOUNT,
            testUser
        );
        
        // 检查最终余额
        uint256 finalUSDC = IERC20(USDC).balanceOf(testUser);
        uint256 finalWETH = IERC20(WETH).balanceOf(testUser);
        
        console2.log('Final USDC balance:', finalUSDC);
        console2.log('Final WETH balance:', finalWETH);
        console2.log('Amount out:', amountOut);
        
        // 验证交换结果
        assertEq(finalUSDC, initialUSDC - TEST_AMOUNT, 'USDC balance should decrease');
        assertGt(finalWETH, initialWETH, 'WETH balance should increase');
        assertGt(amountOut, 0, 'Should receive some WETH');
        
        vm.stopPrank();
        
        console2.log('USDC -> WETH swap successful');
    }
    
    /**
     * @notice 测试 WETH -> USDC 交换
     */
    function test_SwapWETHToUSDC() public {
        uint256 wethAmount = 1 ether; // 1 WETH
        
        // 给测试用户一些 WETH
        deal(WETH, testUser, wethAmount);
        
        vm.startPrank(testUser);
        
        // 检查初始余额
        uint256 initialWETH = IERC20(WETH).balanceOf(testUser);
        uint256 initialUSDC = IERC20(USDC).balanceOf(testUser);
        
        console2.log('Initial WETH balance:', initialWETH);
        console2.log('Initial USDC balance:', initialUSDC);
        
        // 授权路由器使用 WETH（预转账逻辑）
        IERC20(WETH).approve(address(router), wethAmount);
        
        // 执行交换
        uint256 amountOut = router.swapExactTokensForTokens(
            WETH,
            USDC,
            wethAmount,
            MIN_OUTPUT_AMOUNT,
            testUser
        );
        
        // 检查最终余额
        uint256 finalWETH = IERC20(WETH).balanceOf(testUser);
        uint256 finalUSDC = IERC20(USDC).balanceOf(testUser);
        
        console2.log('Final WETH balance:', finalWETH);
        console2.log('Final USDC balance:', finalUSDC);
        console2.log('Amount out:', amountOut);
        
        // 验证交换结果
        assertEq(finalWETH, initialWETH - wethAmount, 'WETH balance should decrease');
        assertGt(finalUSDC, initialUSDC, 'USDC balance should increase');
        assertGt(amountOut, 0, 'Should receive some USDC');
        
        vm.stopPrank();
        
        console2.log('WETH -> USDC swap successful');
    }
    
    /**
     * @notice 测试 USDC -> DAI 交换（稳定币之间）
     */
    function test_SwapUSDCToDAI() public {
        // 给测试用户一些 USDC
        deal(USDC, testUser, TEST_AMOUNT);
        
        vm.startPrank(testUser);
        
        // 检查初始余额
        uint256 initialUSDC = IERC20(USDC).balanceOf(testUser);
        uint256 initialDAI = IERC20(DAI).balanceOf(testUser);
        
        console2.log('Initial USDC balance:', initialUSDC);
        console2.log('Initial DAI balance:', initialDAI);
        
        // 授权路由器使用 USDC（预转账逻辑）
        IERC20(USDC).approve(address(router), TEST_AMOUNT);
        
        // 执行交换
        uint256 amountOut = router.swapExactTokensForTokens(
            USDC,
            DAI,
            TEST_AMOUNT,
            MIN_OUTPUT_AMOUNT,
            testUser
        );
        
        // 检查最终余额
        uint256 finalUSDC = IERC20(USDC).balanceOf(testUser);
        uint256 finalDAI = IERC20(DAI).balanceOf(testUser);
        
        console2.log('Final USDC balance:', finalUSDC);
        console2.log('Final DAI balance:', finalDAI);
        console2.log('Amount out:', amountOut);
        
        // 验证交换结果
        assertEq(finalUSDC, initialUSDC - TEST_AMOUNT, 'USDC balance should decrease');
        assertGt(finalDAI, initialDAI, 'DAI balance should increase');
        assertGt(amountOut, 0, 'Should receive some DAI');
        
        vm.stopPrank();
        
        console2.log('USDC -> DAI swap successful');
    }
    
    /**
     * @notice 测试 CBETH -> WETH 交换（ETH 衍生品之间）
     */
    function test_SwapCBETHToWETH() public {
        uint256 cbethAmount = 1 ether; // 1 CBETH
        
        // 给测试用户一些 CBETH
        deal(CBETH, testUser, cbethAmount);
        
        vm.startPrank(testUser);
        
        // 检查初始余额
        uint256 initialCBETH = IERC20(CBETH).balanceOf(testUser);
        uint256 initialWETH = IERC20(WETH).balanceOf(testUser);
        
        console2.log('Initial CBETH balance:', initialCBETH);
        console2.log('Initial WETH balance:', initialWETH);
        
        // 授权路由器使用 CBETH（预转账逻辑）
        IERC20(CBETH).approve(address(router), cbethAmount);
        
        // 执行交换
        uint256 amountOut = router.swapExactTokensForTokens(
            CBETH,
            WETH,
            cbethAmount,
            MIN_OUTPUT_AMOUNT,
            testUser
        );
        
        // 检查最终余额
        uint256 finalCBETH = IERC20(CBETH).balanceOf(testUser);
        uint256 finalWETH = IERC20(WETH).balanceOf(testUser);
        
        console2.log('Final CBETH balance:', finalCBETH);
        console2.log('Final WETH balance:', finalWETH);
        console2.log('Amount out:', amountOut);
        
        // 验证交换结果
        assertEq(finalCBETH, initialCBETH - cbethAmount, 'CBETH balance should decrease');
        assertGt(finalWETH, initialWETH, 'WETH balance should increase');
        assertGt(amountOut, 0, 'Should receive some WETH');
        
        vm.stopPrank();
        
        console2.log('CBETH -> WETH swap successful');
    }
    
    /**
     * @notice 测试查找最佳交换路径功能（USDC -> WETH）
     */
    function test_FindBestSwapPath() public {
        // 测试 USDC -> WETH 的最佳路径
        MultiVersionUniswapRouter.SwapPath memory path = router.findBestSwapPath(USDC, WETH);
        
        console2.log('Best path version:', uint256(path.version));
        console2.log('Is direct path:', path.isDirectPath);
        console2.log('Expected liquidity:', path.expectedLiquidity);
        console2.log('Token path length:', path.tokens.length);
        
        // 验证路径有效性
        assertGt(path.expectedLiquidity, 0, 'Should find some liquidity');
        assertGe(path.tokens.length, 2, 'Path should have at least 2 tokens');
        assertEq(path.tokens[0], USDC, 'First token should be USDC');
        assertEq(path.tokens[path.tokens.length - 1], WETH, 'Last token should be WETH');
        
        console2.log('Best path finding successful');
    }

    /**
     * @notice 测试查找最佳交换路径功能（WSTETH -> USDC），更可能为多跳
     */
    function test_FindBestSwapPath_WSTETH_USDC() public {
        MultiVersionUniswapRouter.SwapPath memory path = router.findBestSwapPath(WSTETH, USDC);
        console2.log('Best path version (WSTETH->USDC):', uint256(path.version));
        console2.log('Is direct path:', path.isDirectPath);
        console2.log('Expected liquidity:', path.expectedLiquidity);
        console2.log('Token path length:', path.tokens.length);
        assertGt(path.expectedLiquidity, 0, 'Should find some liquidity');
        assertEq(path.tokens[0], WSTETH, 'First token should be WSTETH');
        assertEq(path.tokens[path.tokens.length - 1], USDC, 'Last token should be USDC');
    }
    
    /**
     * @notice 测试余额不足的情况
     */
    function test_InsufficientBalance() public {
        vm.startPrank(testUser);
        
        // 不给用户任何代币，直接尝试交换
        vm.expectRevert('MultiVersionRouter: insufficient balance');
        router.swapExactTokensForTokens(
            USDC,
            WETH,
            TEST_AMOUNT,
            MIN_OUTPUT_AMOUNT,
            testUser
        );
        
        vm.stopPrank();
        
        console2.log('Insufficient balance check successful');
    }
    
    /**
     * @notice 测试相同代币交换的错误处理
     */
    function test_SameTokenSwap() public {
        vm.startPrank(testUser);
        
        vm.expectRevert('MultiVersionRouter: same token swap');
        router.swapExactTokensForTokens(
            USDC,
            USDC,
            TEST_AMOUNT,
            MIN_OUTPUT_AMOUNT,
            testUser
        );
        
        vm.stopPrank();
        
        console2.log('Same token swap check successful');
    }

    /**
     * @notice 测试 USDT -> WETH 交换（覆盖更多稳定币路径）
     */
    function test_SwapUSDTToWETH() public {
        uint256 amount = 1000 * 1e6; // 1000 USDT
        deal(USDT, testUser, amount);
        vm.startPrank(testUser);
        IERC20(USDT).approve(address(router), amount);
        uint256 beforeOut = IERC20(WETH).balanceOf(testUser);
        uint256 out = router.swapExactTokensForTokens(USDT, WETH, amount, MIN_OUTPUT_AMOUNT, testUser);
        uint256 afterOut = IERC20(WETH).balanceOf(testUser);
        assertGt(afterOut, beforeOut, 'WETH should increase');
        assertGt(out, 0, 'Should receive WETH');
        vm.stopPrank();
    }

    /**
     * @notice 测试 WETH -> DAI 交换（ETH -> 稳定币）
     */
    function test_SwapWETHToDAI() public {
        uint256 amount = 1 ether;
        deal(WETH, testUser, amount);
        vm.startPrank(testUser);
        IERC20(WETH).approve(address(router), amount);
        uint256 beforeOut = IERC20(DAI).balanceOf(testUser);
        uint256 out = router.swapExactTokensForTokens(WETH, DAI, amount, MIN_OUTPUT_AMOUNT, testUser);
        uint256 afterOut = IERC20(DAI).balanceOf(testUser);
        assertGt(afterOut, beforeOut, 'DAI should increase');
        assertGt(out, 0, 'Should receive DAI');
        vm.stopPrank();
    }

    /**
     * @notice 测试 WSTETH -> USDC 交换（可能为多跳）
     */
    function test_SwapWSTETHToUSDC() public {
        uint256 amount = 1 ether;
        deal(WSTETH, testUser, amount);

        // 先探测最佳路径版本，避免 Base 上 V4 路径对该交易对出现回滚导致用例不稳定
        MultiVersionUniswapRouter.SwapPath memory path = router.findBestSwapPath(WSTETH, USDC);
        console2.log('Chosen version for WSTETH->USDC:', uint256(path.version));
        console2.log('Is direct path:', path.isDirectPath);

        vm.startPrank(testUser);
        IERC20(WSTETH).approve(address(router), amount);

        uint256 beforeOut = IERC20(USDC).balanceOf(testUser);
        uint256 out = router.swapExactTokensForTokens(WSTETH, USDC, amount, MIN_OUTPUT_AMOUNT, testUser);
        uint256 afterOut = IERC20(USDC).balanceOf(testUser);
        assertGt(afterOut, beforeOut, 'USDC should increase');
        assertGt(out, 0, 'Should receive USDC');
        vm.stopPrank();
    }

    /**
     * @notice 测试检查V4池是否存在
     */
    function test_CheckV4PoolExists() public {
        console2.log('=== Checking V4 Pool Existence ===');
        
        // 检查不同费率的 WSTETH/USDC V4 池子
        uint24[] memory fees = new uint24[](3);
        fees[0] = 3000; // 0.3%
        fees[1] = 500;  // 0.05%
        fees[2] = 100;  // 0.01%
        
        for (uint256 i = 0; i < fees.length; i++) {
            try router.getV4PoolLiquidity(WSTETH, USDC, fees[i]) returns (uint256 liquidity) {
                console2.log('V4 WSTETH/USDC pool fee', fees[i], 'liquidity:', liquidity);
            } catch {
                console2.log('V4 WSTETH/USDC pool fee', fees[i], 'failed to get liquidity');
            }
        }
    }

    /**
     * @notice 测试检查所有版本的流动性
     */
    function test_CheckAllVersionLiquidity() public {
        console2.log('=== Checking All Version Liquidity for WSTETH/USDC ===');
        
        // 获取最佳路径
        MultiVersionUniswapRouter.SwapPath memory path = router.findBestSwapPath(WSTETH, USDC);
        
        console2.log('Best path version:', uint256(path.version));
        console2.log('Best path liquidity:', path.expectedLiquidity);
        console2.log('Is direct path:', path.isDirectPath);
        
        // 检查 V2 流动性
        address v2Pair = V2_FACTORY_INTERFACE.getPair(WSTETH, USDC);
        console2.log('V2 pair address:', v2Pair);
        if (v2Pair != address(0)) {
            try IUniswapV2Pair(v2Pair).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
                console2.log('V2 reserves:', reserve0, reserve1);
            } catch {
                console2.log('V2 failed to get reserves');
            }
        }
        
        // 检查 V3 流动性
        uint24[] memory v3Fees = new uint24[](3);
        v3Fees[0] = 500;
        v3Fees[1] = 3000;
        v3Fees[2] = 100;
        
        for (uint256 i = 0; i < v3Fees.length; i++) {
            address v3Pool = V3_FACTORY_INTERFACE.getPool(WSTETH, USDC, v3Fees[i]);
            console2.log('V3 pool fee', v3Fees[i], 'address:', v3Pool);
            if (v3Pool != address(0)) {
                try IUniswapV3Pool(v3Pool).liquidity() returns (uint128 liquidity) {
                    console2.log('V3 fee', v3Fees[i], 'liquidity:', liquidity);
                } catch {
                    console2.log('V3 fee', v3Fees[i], 'failed to get liquidity');
                }
            }
        }
        
        // 检查 V4 流动性
        uint24[] memory v4Fees = new uint24[](3);
        v4Fees[0] = 500;
        v4Fees[1] = 3000;
        v4Fees[2] = 100;
        
        for (uint256 i = 0; i < v4Fees.length; i++) {
            try router.getV4PoolLiquidity(WSTETH, USDC, v4Fees[i]) returns (uint256 liquidity) {
                console2.log('V4 fee', v4Fees[i], 'liquidity:', liquidity);
            } catch {
                console2.log('V4 fee', v4Fees[i], 'failed to get liquidity');
            }
        }
    }

    /**
     * @notice 测试 CBETH -> USDC 交换（多跳覆盖）
     */
    function test_SwapCBETHToUSDC() public {
        uint256 amount = 1 ether;
        deal(CBETH, testUser, amount);
        vm.startPrank(testUser);
        IERC20(CBETH).approve(address(router), amount);
        uint256 beforeOut = IERC20(USDC).balanceOf(testUser);
        uint256 out = router.swapExactTokensForTokens(CBETH, USDC, amount, MIN_OUTPUT_AMOUNT, testUser);
        uint256 afterOut = IERC20(USDC).balanceOf(testUser);
        assertGt(afterOut, beforeOut, 'USDC should increase');
        assertGt(out, 0, 'Should receive USDC');
        vm.stopPrank();
    }

    /**
     * @notice 测试接收人非 msg.sender 的场景
     */
    function test_SwapToDifferentRecipient() public {
        address recipient = makeAddr('recipient');
        deal(USDC, testUser, TEST_AMOUNT);
        vm.startPrank(testUser);
        IERC20(USDC).approve(address(router), TEST_AMOUNT);
        uint256 beforeRecipient = IERC20(WETH).balanceOf(recipient);
        uint256 beforeSender = IERC20(USDC).balanceOf(testUser);
        uint256 out = router.swapExactTokensForTokens(USDC, WETH, TEST_AMOUNT, MIN_OUTPUT_AMOUNT, recipient);
        uint256 afterRecipient = IERC20(WETH).balanceOf(recipient);
        uint256 afterSender = IERC20(USDC).balanceOf(testUser);
        assertEq(afterSender, beforeSender - TEST_AMOUNT, 'Sender USDC should decrease by amountIn');
        assertGt(afterRecipient, beforeRecipient, 'Recipient should receive tokenOut');
        assertGt(out, 0, 'Amount out > 0');
        vm.stopPrank();
    }

    /**
     * @notice 测试极端滑点（minOut 过大）应该回滚
     */
    function test_SwapMinOutputTooHigh_Revert() public {
        deal(USDC, testUser, TEST_AMOUNT);
        vm.startPrank(testUser);
        IERC20(USDC).approve(address(router), TEST_AMOUNT);
        vm.expectRevert(); // 由 UR 或本合约的最小输出检查导致回滚
        router.swapExactTokensForTokens(USDC, WETH, TEST_AMOUNT, type(uint128).max, testUser);
        vm.stopPrank();
    }

    /**
     * @notice 测试接收人地址为 0 应回滚
     */
    function test_RecipientZeroAddress_Revert() public {
        deal(USDC, testUser, TEST_AMOUNT);
        vm.startPrank(testUser);
        IERC20(USDC).approve(address(router), TEST_AMOUNT);
        vm.expectRevert('MultiVersionRouter: invalid recipient');
        router.swapExactTokensForTokens(USDC, WETH, TEST_AMOUNT, MIN_OUTPUT_AMOUNT, address(0));
        vm.stopPrank();
    }

    /**
     * @notice 测试 amountIn 为 0 应回滚
     */
    function test_AmountZero_Revert() public {
        vm.startPrank(testUser);
        vm.expectRevert('MultiVersionRouter: invalid amount');
        router.swapExactTokensForTokens(USDC, WETH, 0, MIN_OUTPUT_AMOUNT, testUser);
        vm.stopPrank();
    }

    /**
     * @notice 测试不存在路径时应回滚（使用本地部署的无流动性代币）
     */
    function test_NoValidPath_Revert() public {
        // 部署无任何池子的本地代币并铸造给用户
        MockERC20 mock = new MockERC20('Mock Token', 'MCK', 18);
        mock.mint(testUser, 10 ether);
        vm.startPrank(testUser);
        IERC20(address(mock)).approve(address(router), 1 ether);
        vm.expectRevert('MultiVersionRouter: no valid swap path found');
        router.swapExactTokensForTokens(address(mock), USDC, 1 ether, MIN_OUTPUT_AMOUNT, testUser);
        vm.stopPrank();
    }

    /**
     * @notice 测试 SwapExecuted 事件（仅校验 topics，不校验 data）
     */
    function test_Events_OnSwapExecuted() public {
        deal(USDC, testUser, TEST_AMOUNT);
        vm.startPrank(testUser);
        IERC20(USDC).approve(address(router), TEST_AMOUNT);
        vm.expectEmit(true, true, true, false);
        emit MultiVersionUniswapRouter.SwapExecuted(USDC, WETH, 0, 0, MultiVersionUniswapRouter.UniswapVersion.V2, testUser);
        router.swapExactTokensForTokens(USDC, WETH, TEST_AMOUNT, MIN_OUTPUT_AMOUNT, testUser);
        vm.stopPrank();
    }

    /**
     * @notice 测试 BestPathFound 事件（仅校验前两个 indexed topics）
     */
    function test_Events_OnBestPathFound() public {
        vm.expectEmit(true, true, false, false);
        emit MultiVersionUniswapRouter.BestPathFound(USDC, WETH, MultiVersionUniswapRouter.UniswapVersion.V2, 0, true);
        router.findBestSwapPath(USDC, WETH);
    }
}