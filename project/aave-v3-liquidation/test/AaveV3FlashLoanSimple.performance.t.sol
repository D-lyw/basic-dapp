// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console2} from 'forge-std/Test.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';
import {MultiVersionUniswapRouter} from '../src/MultiVersionUniswapRouter.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IPool} from 'aave-v3-origin/src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol';

/**
 * @title AaveV3FlashLoanSimple 性能测试套件
 * @notice 专门测试清算合约的性能和 gas 优化效果
 * @dev 包含 gas 使用量测试、性能基准测试、优化效果验证等
 */
contract AaveV3FlashLoanSimplePerformanceTest is Test {
    AaveV3FlashLoanSimple public liquidation;
    MultiVersionUniswapRouter public multiRouter;
    
    // Base Mainnet 地址
    address constant AAVE_POOL_ADDRESSES_PROVIDER = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    // Uniswap 工厂地址
    address constant V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address constant V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    
    uint256 constant FORK_BLOCK_NUMBER = 34982557;
    
    address deployer;
    address testUser;
    
    // Gas 使用量记录
    struct GasMetrics {
        uint256 deployment;
        uint256 updateBuilderPayment;
        uint256 pause;
        uint256 unpause;
        uint256 withdrawETH;
        uint256 withdrawToken;
        uint256 executeLiquidationAttempt;
    }
    
    GasMetrics public gasMetrics;
    
    function setUp() public {
        // 创建 Base mainnet fork
        vm.createFork(vm.envString('BASE_MAINNET_RPC_URL'), FORK_BLOCK_NUMBER);
        vm.selectFork(0);
        
        // 设置测试账户
        deployer = makeAddr('deployer');
        testUser = makeAddr('testUser');
        
        // 给测试账户一些 ETH
        vm.deal(deployer, 100 ether);
        vm.deal(testUser, 10 ether);
        
        // 部署合约并记录 gas
        vm.startPrank(deployer);
        
        uint256 gasBefore = gasleft();
        
        multiRouter = new MultiVersionUniswapRouter(
            UNIVERSAL_ROUTER,
            PERMIT2,
            V2_FACTORY,
            V3_FACTORY,
            POOL_MANAGER,
            WETH,
            USDC
        );
        
        liquidation = new AaveV3FlashLoanSimple(
            AAVE_POOL_ADDRESSES_PROVIDER,
            address(multiRouter),
            WETH,
            10 // 10% builder payment
        );
        
        gasMetrics.deployment = gasBefore - gasleft();
        
        vm.stopPrank();
    }
    
    // ============ 部署成本测试 ============
    
    function test_Performance_DeploymentCost() public view {
        console2.log('=== Deployment Gas Costs ===');
        console2.log('Total deployment gas:', gasMetrics.deployment);
        
        // 验证部署成本在合理范围内
        assertTrue(gasMetrics.deployment > 0, 'Deployment should consume gas');
        assertTrue(gasMetrics.deployment < 5_000_000, 'Deployment cost should be reasonable');
        
        console2.log('Deployment cost check: PASSED');
    }
    
    // ============ 基本操作 Gas 测试 ============
    
    function test_Performance_UpdateBuilderPaymentGas() public {
        vm.startPrank(deployer);
        
        // 测试多次更新的 gas 使用
        uint256[] memory percentages = new uint256[](5);
        percentages[0] = 0;
        percentages[1] = 25;
        percentages[2] = 50;
        percentages[3] = 75;
        percentages[4] = 99;
        
        uint256 totalGas = 0;
        uint256 minGas = type(uint256).max;
        uint256 maxGas = 0;
        
        for (uint i = 0; i < percentages.length; i++) {
            uint256 gasBefore = gasleft();
            liquidation.updateBuilderPaymentPercentage(percentages[i]);
            uint256 gasUsed = gasBefore - gasleft();
            
            totalGas += gasUsed;
            if (gasUsed < minGas) minGas = gasUsed;
            if (gasUsed > maxGas) maxGas = gasUsed;
            
            console2.log('Update to', percentages[i], '% gas:', gasUsed);
        }
        
        uint256 avgGas = totalGas / percentages.length;
        gasMetrics.updateBuilderPayment = avgGas;
        
        console2.log('=== UpdateBuilderPayment Gas Analysis ===');
        console2.log('Average gas:', avgGas);
        console2.log('Min gas:', minGas);
        console2.log('Max gas:', maxGas);
        console2.log('Gas variance:', maxGas - minGas);
        
        // 验证 gas 使用在合理范围内
        assertTrue(avgGas < 50_000, 'Average gas should be reasonable');
        assertTrue(maxGas - minGas < 10_000, 'Gas variance should be low');
        
        vm.stopPrank();
    }
    
    function test_Performance_PauseUnpauseGas() public {
        vm.startPrank(deployer);
        
        // 测试暂停操作的 gas
        uint256 gasBefore = gasleft();
        liquidation.pause();
        gasMetrics.pause = gasBefore - gasleft();
        
        // 测试恢复操作的 gas
        gasBefore = gasleft();
        liquidation.unpause();
        gasMetrics.unpause = gasBefore - gasleft();
        
        console2.log('=== Pause/Unpause Gas Analysis ===');
        console2.log('Pause gas:', gasMetrics.pause);
        console2.log('Unpause gas:', gasMetrics.unpause);
        
        // 验证 gas 使用在合理范围内
        assertTrue(gasMetrics.pause < 50_000, 'Pause gas should be reasonable');
        assertTrue(gasMetrics.unpause < 50_000, 'Unpause gas should be reasonable');
        
        vm.stopPrank();
    }
    
    function test_Performance_WithdrawOperationsGas() public {
        // 给合约一些资金
        vm.deal(address(liquidation), 10 ether);
        deal(USDC, address(liquidation), 10000e6);
        
        vm.startPrank(deployer);
        
        // 测试 ETH 提取的 gas
        uint256 gasBefore = gasleft();
        liquidation.withdrawETH(1 ether);
        gasMetrics.withdrawETH = gasBefore - gasleft();
        
        // 测试代币提取的 gas
        gasBefore = gasleft();
        liquidation.withdrawToken(USDC, 1000e6);
        gasMetrics.withdrawToken = gasBefore - gasleft();
        
        console2.log('=== Withdraw Operations Gas Analysis ===');
        console2.log('WithdrawETH gas:', gasMetrics.withdrawETH);
        console2.log('WithdrawToken gas:', gasMetrics.withdrawToken);
        
        // 验证 gas 使用在合理范围内
        assertTrue(gasMetrics.withdrawETH < 50_000, 'WithdrawETH gas should be reasonable');
        assertTrue(gasMetrics.withdrawToken < 100_000, 'WithdrawToken gas should be reasonable');
        
        vm.stopPrank();
    }
    
    // ============ 清算操作 Gas 测试 ============
    
    function test_Performance_ExecuteLiquidationAttemptGas() public {
        vm.startPrank(deployer);
        
        // 测试清算尝试的 gas（预期会失败，但我们关心 gas 使用）
        uint256 gasBefore = gasleft();
        
        try liquidation.executeLiquidation(
            WETH,
            USDC,
            testUser,
            1000e6,
            false,
            block.timestamp + 300,
            false
        ) {
            // 不应该到达这里
            assertTrue(false, 'Liquidation should fail without proper setup');
        } catch {
            gasMetrics.executeLiquidationAttempt = gasBefore - gasleft();
        }
        
        console2.log('=== ExecuteLiquidation Attempt Gas Analysis ===');
        console2.log('ExecuteLiquidation attempt gas:', gasMetrics.executeLiquidationAttempt);
        
        // 验证即使失败，gas 使用也在合理范围内
        assertTrue(gasMetrics.executeLiquidationAttempt > 0, 'Should consume some gas');
        assertTrue(gasMetrics.executeLiquidationAttempt < 500_000, 'Failed liquidation gas should be reasonable');
        
        vm.stopPrank();
    }
    
    // ============ 批量操作性能测试 ============
    
    function test_Performance_BatchOperations() public {
        vm.startPrank(deployer);
        
        console2.log('=== Batch Operations Performance ===');
        
        // 测试批量更新 builder payment
        uint256 gasBefore = gasleft();
        for (uint i = 0; i < 10; i++) {
            liquidation.updateBuilderPaymentPercentage(i * 10);
        }
        uint256 batchUpdateGas = gasBefore - gasleft();
        
        console2.log('10x updateBuilderPayment gas:', batchUpdateGas);
        console2.log('Average per update:', batchUpdateGas / 10);
        
        // 测试批量暂停/恢复
        gasBefore = gasleft();
        for (uint i = 0; i < 5; i++) {
            liquidation.pause();
            liquidation.unpause();
        }
        uint256 batchPauseGas = gasBefore - gasleft();
        
        console2.log('5x pause/unpause cycles gas:', batchPauseGas);
        console2.log('Average per cycle:', batchPauseGas / 5);
        
        // 验证批量操作的效率
        assertTrue(batchUpdateGas / 10 < 50_000, 'Batch update efficiency should be maintained');
        assertTrue(batchPauseGas / 5 < 100_000, 'Batch pause/unpause efficiency should be maintained');
        
        vm.stopPrank();
    }
    
    // ============ 内存使用优化测试 ============
    
    function test_Performance_MemoryUsage() public {
        vm.startPrank(deployer);
        
        console2.log('=== Memory Usage Analysis ===');
        
        // 测试大量状态读取的 gas 效率
        uint256 gasBefore = gasleft();
        
        for (uint i = 0; i < 100; i++) {
            // 读取状态变量
            liquidation.builderPaymentPercentage();
            liquidation.paused();
            liquidation.owner();
        }
        
        uint256 stateReadGas = gasBefore - gasleft();
        
        console2.log('100x state reads gas:', stateReadGas);
        console2.log('Average per read:', stateReadGas / 100);
        
        // 验证状态读取效率
        assertTrue(stateReadGas / 100 < 3000, 'State read efficiency should be high');
        
        vm.stopPrank();
    }
    
    // ============ 存储优化测试 ============
    
    function test_Performance_StorageOptimization() public {
        vm.startPrank(deployer);
        
        console2.log('=== Storage Optimization Analysis ===');
        
        // 测试存储写入的 gas 成本
        uint256 gasBefore = gasleft();
        liquidation.updateBuilderPaymentPercentage(50);
        uint256 storageWriteGas = gasBefore - gasleft();
        
        // 测试相同值的重复写入（应该更便宜）
        gasBefore = gasleft();
        liquidation.updateBuilderPaymentPercentage(50);
        uint256 sameValueWriteGas = gasBefore - gasleft();
        
        console2.log('First storage write gas:', storageWriteGas);
        console2.log('Same value write gas:', sameValueWriteGas);
        console2.log('Gas savings for same value:', storageWriteGas - sameValueWriteGas);
        
        // 验证存储优化效果
        assertTrue(sameValueWriteGas <= storageWriteGas, 'Same value write should not cost more');
        
        vm.stopPrank();
    }
    
    // ============ 函数调用开销测试 ============
    
    function test_Performance_FunctionCallOverhead() public {
        vm.startPrank(deployer);
        
        console2.log('=== Function Call Overhead Analysis ===');
        
        // 测试 view 函数调用开销
        uint256 gasBefore = gasleft();
        for (uint i = 0; i < 50; i++) {
            liquidation.builderPaymentPercentage();
        }
        uint256 viewCallGas = gasBefore - gasleft();
        
        // 测试 pure 函数调用开销（如果有的话）
        gasBefore = gasleft();
        for (uint i = 0; i < 50; i++) {
            liquidation.owner();
        }
        uint256 ownerCallGas = gasBefore - gasleft();
        
        console2.log('50x builderPaymentPercentage() calls gas:', viewCallGas);
        console2.log('50x owner() calls gas:', ownerCallGas);
        console2.log('Average view call gas:', viewCallGas / 50);
        console2.log('Average owner call gas:', ownerCallGas / 50);
        
        // 验证函数调用效率
        assertTrue(viewCallGas / 50 < 2000, 'View function calls should be efficient');
        assertTrue(ownerCallGas / 50 < 1500, 'Owner function calls should be efficient');
        
        vm.stopPrank();
    }
    
    // ============ 事件发射成本测试 ============
    
    function test_Performance_EventEmissionCost() public {
        vm.startPrank(deployer);
        
        console2.log('=== Event Emission Cost Analysis ===');
        
        // 测试带事件的操作 vs 不带事件的操作
        uint256 gasBefore = gasleft();
        liquidation.updateBuilderPaymentPercentage(30);
        uint256 withEventGas = gasBefore - gasleft();
        
        // 再次更新（相同值，但仍会发射事件）
        gasBefore = gasleft();
        liquidation.updateBuilderPaymentPercentage(30);
        uint256 sameValueEventGas = gasBefore - gasleft();
        
        console2.log('Update with event gas:', withEventGas);
        console2.log('Same value update with event gas:', sameValueEventGas);
        
        // 验证事件发射成本合理
        assertTrue(withEventGas > 0, 'Event emission should have cost');
        assertTrue(withEventGas < 100_000, 'Event emission cost should be reasonable');
        
        vm.stopPrank();
    }
    
    // ============ 综合性能报告 ============
    
    function test_Performance_ComprehensiveReport() public {
        // 运行所有性能测试以收集数据
        test_Performance_UpdateBuilderPaymentGas();
        test_Performance_PauseUnpauseGas();
        test_Performance_WithdrawOperationsGas();
        test_Performance_ExecuteLiquidationAttemptGas();
        
        console2.log('\n=== COMPREHENSIVE PERFORMANCE REPORT ===');
        console2.log('Deployment Gas:', gasMetrics.deployment);
        console2.log('Update Builder Payment Gas:', gasMetrics.updateBuilderPayment);
        console2.log('Pause Gas:', gasMetrics.pause);
        console2.log('Unpause Gas:', gasMetrics.unpause);
        console2.log('Withdraw ETH Gas:', gasMetrics.withdrawETH);
        console2.log('Withdraw Token Gas:', gasMetrics.withdrawToken);
        console2.log('Execute Liquidation Attempt Gas:', gasMetrics.executeLiquidationAttempt);
        
        // 计算总体性能评分
        uint256 totalOperationalGas = gasMetrics.updateBuilderPayment + 
                                     gasMetrics.pause + 
                                     gasMetrics.unpause + 
                                     gasMetrics.withdrawETH + 
                                     gasMetrics.withdrawToken;
        
        console2.log('Total Operational Gas (excluding liquidation):', totalOperationalGas);
        console2.log('Average Operational Gas:', totalOperationalGas / 5);
        
        // 性能基准验证
        assertTrue(gasMetrics.deployment < 5_000_000, 'Deployment should be under 5M gas');
        assertTrue(totalOperationalGas < 500_000, 'Total operational gas should be under 500K');
        assertTrue(gasMetrics.executeLiquidationAttempt < 500_000, 'Liquidation attempt should be under 500K gas');
        
        console2.log('\n=== PERFORMANCE BENCHMARKS: ALL PASSED ===');
    }
    
    // ============ Gas 优化建议测试 ============
    
    function test_Performance_OptimizationSuggestions() public view {
        console2.log('\n=== GAS OPTIMIZATION ANALYSIS ===');
        
        // 分析当前的 gas 使用模式并提供建议
        if (gasMetrics.updateBuilderPayment > 30_000) {
            console2.log('SUGGESTION: Consider optimizing updateBuilderPaymentPercentage function');
        }
        
        if (gasMetrics.withdrawETH > 30_000) {
            console2.log('SUGGESTION: Consider optimizing withdrawETH function');
        }
        
        if (gasMetrics.withdrawToken > 50_000) {
            console2.log('SUGGESTION: Consider optimizing withdrawToken function');
        }
        
        if (gasMetrics.executeLiquidationAttempt > 300_000) {
            console2.log('SUGGESTION: Consider optimizing executeLiquidation function');
        }
        
        console2.log('Gas optimization analysis completed.');
    }
    
    // ============ 压力测试 ============
    
    function test_Performance_StressTest() public {
        vm.startPrank(deployer);
        
        console2.log('=== STRESS TEST ===');
        
        // 大量连续操作的压力测试
        uint256 iterations = 20;
        uint256 gasBefore = gasleft();
        
        for (uint i = 0; i < iterations; i++) {
            liquidation.updateBuilderPaymentPercentage(i % 100);
            if (i % 2 == 0) {
                liquidation.pause();
                liquidation.unpause();
            }
        }
        
        uint256 stressTestGas = gasBefore - gasleft();
        
        console2.log('Stress test iterations:', iterations);
        console2.log('Total stress test gas:', stressTestGas);
        console2.log('Average gas per iteration:', stressTestGas / iterations);
        
        // 验证压力测试结果
        assertTrue(stressTestGas / iterations < 100_000, 'Stress test efficiency should be maintained');
        
        vm.stopPrank();
    }
    
    // 接收 ETH
    receive() external payable {}
}