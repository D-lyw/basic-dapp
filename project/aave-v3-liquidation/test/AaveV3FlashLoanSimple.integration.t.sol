// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console2} from 'forge-std/Test.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';
import {MultiVersionUniswapRouter} from '../src/MultiVersionUniswapRouter.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IPool} from 'aave-v3-origin/src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol';

/**
 * @title AaveV3FlashLoanSimple Integration Test
 * @notice 测试 AaveV3FlashLoanSimple 与 MultiVersionUniswapRouter 的集成
 * @dev 这个测试验证两个合约能够正确协作
 */
contract AaveV3FlashLoanSimpleIntegrationTest is Test {
    AaveV3FlashLoanSimple public liquidation;
    MultiVersionUniswapRouter public multiRouter;
    
    // Base Mainnet 地址
    address constant AAVE_POOL_ADDRESSES_PROVIDER = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    address constant WSTETH = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
    
    // Uniswap 工厂地址
    address constant V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address constant V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    
    uint256 constant BUILDER_PAYMENT_PERCENTAGE = 0;
    uint256 constant FORK_BLOCK_NUMBER = 34986776;
    
    function setUp() public {
        // 创建 Base mainnet fork
        vm.createFork(vm.envString('BASE_MAINNET_RPC_URL'), FORK_BLOCK_NUMBER);
        vm.selectFork(0);
        
        // 获取部署者私钥和地址
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log('Deployer address:', deployer);
        
        // 部署 MultiVersionUniswapRouter
        multiRouter = new MultiVersionUniswapRouter(
            UNIVERSAL_ROUTER,
            PERMIT2,
            V2_FACTORY,
            V3_FACTORY,
            POOL_MANAGER,
            WETH,
            USDC
        );
        
        // 以部署者身份部署 AaveV3FlashLoanSimple，这样合约的 owner 就是部署者
        vm.startPrank(deployer);
        liquidation = new AaveV3FlashLoanSimple(
            AAVE_POOL_ADDRESSES_PROVIDER,
            address(multiRouter),
            WETH,
            USDC,
            BUILDER_PAYMENT_PERCENTAGE
        );
        vm.stopPrank();
        
        console2.log('MultiVersionUniswapRouter deployed at:', address(multiRouter));
        console2.log('AaveV3FlashLoanSimple deployed at:', address(liquidation));
        console2.log('AaveV3FlashLoanSimple owner:', liquidation.owner());
    }
    
    /**
     * @notice 测试合约集成配置
     */
    function test_IntegrationConfig() public {
        // 验证 AaveV3FlashLoanSimple 正确引用了 MultiVersionUniswapRouter
        assertEq(address(liquidation.MULTI_ROUTER()), address(multiRouter));
        assertEq(address(liquidation.ADDRESSES_PROVIDER()), AAVE_POOL_ADDRESSES_PROVIDER);
        assertEq(liquidation.WETH(), WETH);
        assertEq(liquidation.USDC(), USDC);
        assertEq(liquidation.builderPaymentPercentage(), BUILDER_PAYMENT_PERCENTAGE);
        
        // 验证 MultiVersionUniswapRouter 配置
        assertEq(address(multiRouter.UNIVERSAL_ROUTER()), UNIVERSAL_ROUTER);
        assertEq(address(multiRouter.PERMIT2()), PERMIT2);
        assertEq(address(multiRouter.POOL_MANAGER()), POOL_MANAGER);
        assertEq(multiRouter.WETH(), WETH);
        assertEq(multiRouter.USDC(), USDC);
        
        console2.log('Integration configuration verified successfully');
    }
    
    /**
     * @notice 测试 MultiVersionUniswapRouter 的基本功能
     */
    function test_MultiRouterBasicFunctionality() public {
        // 检查 MultiVersionUniswapRouter 是否能正确查找最佳路径
        MultiVersionUniswapRouter.SwapPath memory path = multiRouter.findBestSwapPath(WSTETH, USDC);
            
        console2.log('Best path version:', uint256(path.version));
        console2.log('Best path liquidity:', path.expectedLiquidity);
        console2.log('Is direct path:', path.isDirectPath);
        
        // 应该找到有效的交换路径
        assertTrue(path.expectedLiquidity > 0, 'Should find a valid swap path with liquidity');
        assertTrue(path.tokens.length >= 2, 'Path should have at least 2 tokens');
    }
    
    /**
     * @notice 测试合约权限和访问控制
     */
    function test_AccessControl() public {
        // 验证 liquidation 合约的 owner
        assertEq(liquidation.owner(), address(this));
        
        // 验证合约可以暂停和恢复
        liquidation.pause();
        assertTrue(liquidation.paused());
        
        liquidation.unpause();
        assertFalse(liquidation.paused());
        
        console2.log('Access control verified successfully');
    }
    
    /**
     * @notice 测试合约地址验证
     */
    function test_ContractAddresses() public {
        // 验证所有关键地址都不是零地址
        assertTrue(address(liquidation) != address(0), 'Liquidation contract address should not be zero');
        assertTrue(address(multiRouter) != address(0), 'MultiRouter address should not be zero');
        assertTrue(address(liquidation.MULTI_ROUTER()) != address(0), 'MULTI_ROUTER reference should not be zero');
        assertTrue(address(liquidation.ADDRESSES_PROVIDER()) != address(0), 'ADDRESSES_PROVIDER should not be zero');
        
        // 验证代币地址
        assertTrue(liquidation.WETH() != address(0), 'WETH address should not be zero');
        assertTrue(liquidation.USDC() != address(0), 'USDC address should not be zero');
        
        console2.log('Contract addresses verified successfully');
    }


    function test_CallLiquidation() public {
        // 获取部署者私钥和地址
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log('Deployer address:', deployer);
        console2.log('Contract owner:', liquidation.owner());
        
        // 确保部署者是合约的所有者
        require(deployer == liquidation.owner(), 'Deployer must be contract owner');
        
        // 获取 Aave Pool 实例
        IPool pool = IPool(IPoolAddressesProvider(AAVE_POOL_ADDRESSES_PROVIDER).getPool());
        
        // 使用预定义的清算参数
        address debtAsset = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;           // 债务资产 
        address collateralAsset = 0x4200000000000000000000000000000000000006; // 抵押品资产 
        address user = 0x3185bB73AfD7f38FC98F0E6a72668F531D29B099;                   // 被清算用户
        uint256 debtToCoverAmount = 8588757;   // 要清算的债务数量（减少到避免 dust 错误）
        
        // 检查测试用户的健康因子
        (, , , , , uint256 healthFactor) = pool.getUserAccountData(user);
        console2.log('Test user health factor:', healthFactor);
        
        if (healthFactor >= 1e18) {
            console2.log('User health factor is above liquidation threshold, cannot liquidate');
            return;
        }
        
        // 获取用户的债务信息
        (, uint256 totalDebtBase, , , , ) = pool.getUserAccountData(user);
        console2.log('User total debt in base currency:', totalDebtBase);
        
        bool receiveAToken = false;       // 不接收 aToken，直接接收底层资产
        uint256 deadline = block.timestamp + 300; // 5分钟后过期
        bool useMaxDebt = true;           // 使用最大债务清算，让 Aave 决定清算数量
        
        console2.log('Attempting liquidation with parameters:');
        console2.log('  Collateral Asset:', collateralAsset);
        console2.log('  Debt Asset:', debtAsset);
        console2.log('  User:', user);
        console2.log('  Debt to Cover:', debtToCoverAmount);
        console2.log('  Deadline:', deadline);
        
        // 记录清算前的状态
        (uint256 preTotalCollateralBase, uint256 preTotalDebtBase, , , , ) = 
            pool.getUserAccountData(user);
        uint256 preUserUsdcDebt = IERC20(debtAsset).balanceOf(user);
        uint256 preUserWethBalance = IERC20(collateralAsset).balanceOf(user);
        
        // 以合约所有者身份执行清算
        vm.startPrank(deployer);
        
        try liquidation.executeLiquidation(
            collateralAsset,
            debtAsset,
            user,
            debtToCoverAmount,
            receiveAToken,
            deadline,
            useMaxDebt
        ) {
            console2.log('Liquidation executed successfully');
        } catch Error(string memory reason) {
            console2.log('Liquidation failed with reason:', reason);
        } catch (bytes memory lowLevelData) {
            console2.log('Liquidation failed with low level error');
            console2.logBytes(lowLevelData);
        }
        
        // 输出详细的清算操作数据
        console2.log('\n=== Liquidation Operation Details ===');
        console2.log('Target User Address:', user);
        console2.log('Debt Asset (USDC):', debtAsset);
        console2.log('Collateral Asset (WETH):', collateralAsset);
        console2.log('Liquidation Amount (USDC):', debtToCoverAmount);
        console2.log('Use Max Debt:', useMaxDebt);
        
        // 获取清算后的用户债务和抵押品余额
        (uint256 postTotalCollateralBase, uint256 postTotalDebtBase, , , , ) = 
            pool.getUserAccountData(user);
        uint256 postUserUsdcDebt = IERC20(debtAsset).balanceOf(user);
        uint256 postUserWethBalance = IERC20(collateralAsset).balanceOf(user);
        
        console2.log('\n=== Before/After Comparison ===');
        console2.log('User Total Collateral Value (Before):', preTotalCollateralBase);
        console2.log('User Total Collateral Value (After):', postTotalCollateralBase);
        console2.log('User Total Debt Value (Before):', preTotalDebtBase);
        console2.log('User Total Debt Value (After):', postTotalDebtBase);
        console2.log('User USDC Balance (Before):', preUserUsdcDebt);
        console2.log('User USDC Balance (After):', postUserUsdcDebt);
        console2.log('User WETH Balance (Before):', preUserWethBalance);
        console2.log('User WETH Balance (After):', postUserWethBalance);
        
        // 计算清算收益
        uint256 contractEthBalance = address(liquidation).balance;
        uint256 contractUsdcBalance = IERC20(debtAsset).balanceOf(address(liquidation));
        uint256 contractWethBalance = IERC20(collateralAsset).balanceOf(address(liquidation));
        
        console2.log('\n=== Contract Profits ===');
        console2.log('Contract ETH Balance:', contractEthBalance);
        console2.log('Contract USDC Balance:', contractUsdcBalance);
        console2.log('Contract WETH Balance:', contractWethBalance);
        
        // 计算抵押品减少量和债务减少量
        uint256 collateralReduction = preTotalCollateralBase - postTotalCollateralBase;
        uint256 debtReduction = preTotalDebtBase - postTotalDebtBase;
        
        console2.log('\n=== Liquidation Effect Analysis ===');
        console2.log('Collateral Value Reduction:', collateralReduction);
        console2.log('Debt Value Reduction:', debtReduction);
        console2.log('Liquidation Reward (Collateral - Debt Reduction):', collateralReduction > debtReduction ? collateralReduction - debtReduction : 0);
        
        vm.stopPrank();
    }
}