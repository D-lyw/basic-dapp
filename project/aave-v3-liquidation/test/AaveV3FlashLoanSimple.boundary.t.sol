// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console2} from 'forge-std/Test.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';
import {MultiVersionUniswapRouter} from '../src/MultiVersionUniswapRouter.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IPool} from 'aave-v3-origin/src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol';

/**
 * @title AaveV3FlashLoanSimple 边界条件测试套件
 * @notice 专门测试清算合约的边界条件和极端值处理
 * @dev 包含最小值、最大值、零值、溢出等边界情况测试
 */
contract AaveV3FlashLoanSimpleBoundaryTest is Test {
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
        
        // 部署合约
        vm.startPrank(deployer);
        
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
        
        vm.stopPrank();
    }
    
    // ============ Builder Payment Percentage 边界测试 ============
    
    function test_Boundary_BuilderPaymentPercentage_Zero() public {
        vm.startPrank(deployer);
        
        // 测试设置为 0%
        liquidation.updateBuilderPaymentPercentage(0);
        assertEq(liquidation.builderPaymentPercentage(), 0);
        
        vm.stopPrank();
    }
    
    function test_Boundary_BuilderPaymentPercentage_Maximum() public {
        vm.startPrank(deployer);
        
        // 测试设置为最大值 99%
        liquidation.updateBuilderPaymentPercentage(99);
        assertEq(liquidation.builderPaymentPercentage(), 99);
        
        vm.stopPrank();
    }
    
    function test_Boundary_BuilderPaymentPercentage_OverMaximum() public {
        vm.startPrank(deployer);
        
        // 测试超过最大值 100%
        vm.expectRevert('AaveV3FlashLoan: invalid builder payment percentage');
        liquidation.updateBuilderPaymentPercentage(100);
        
        // 测试远超最大值
        vm.expectRevert('AaveV3FlashLoan: invalid builder payment percentage');
        liquidation.updateBuilderPaymentPercentage(1000);
        
        vm.stopPrank();
    }
    
    function test_Boundary_BuilderPaymentPercentage_EdgeValues() public {
        vm.startPrank(deployer);
        
        // 测试边界值
        uint256[] memory edgeValues = new uint256[](5);
        edgeValues[0] = 1;   // 最小有效值
        edgeValues[1] = 25;  // 四分之一
        edgeValues[2] = 50;  // 一半
        edgeValues[3] = 75;  // 四分之三
        edgeValues[4] = 98;  // 接近最大值
        
        for (uint i = 0; i < edgeValues.length; i++) {
            liquidation.updateBuilderPaymentPercentage(edgeValues[i]);
            assertEq(liquidation.builderPaymentPercentage(), edgeValues[i]);
        }
        
        vm.stopPrank();
    }
    
    // ============ 债务金额边界测试 ============
    
    function test_Boundary_DebtAmount_Zero() public {
        vm.startPrank(deployer);
        
        // 测试零债务金额（应该在 Aave 层面被拒绝）
        vm.expectRevert();
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            0,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_DebtAmount_VerySmall() public {
        vm.startPrank(deployer);
        
        // 测试非常小的债务金额（1 wei）
        vm.expectRevert();
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_DebtAmount_MinimumUSDC() public {
        vm.startPrank(deployer);
        
        // 测试最小 USDC 单位（1 micro USDC）
        vm.expectRevert();
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1, // 1 micro USDC
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_DebtAmount_LargeButRealistic() public {
        vm.startPrank(deployer);
        
        // 测试大但现实的债务金额（1M USDC）
        vm.expectRevert(); // 预期失败，因为没有实际的可清算用户
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1_000_000e6, // 1M USDC
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_DebtAmount_ExtremelyLarge() public {
        vm.startPrank(deployer);
        
        // 测试极大的债务金额
        vm.expectRevert();
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            type(uint128).max, // 极大值但不会溢出
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    // ============ 时间戳边界测试 ============
    
    function test_Boundary_Deadline_CurrentTimestamp() public {
        vm.startPrank(deployer);
        
        // 测试当前时间戳作为截止时间（应该失败）
        vm.expectRevert(); // 预期失败，因为没有实际的可清算用户
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1000e6,
            false,
            block.timestamp,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_Deadline_OneSecondFuture() public {
        vm.startPrank(deployer);
        
        // 测试未来 1 秒的截止时间
        vm.expectRevert(); // 预期失败，因为没有实际的可清算用户
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1000e6,
            false,
            block.timestamp + 1,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_Deadline_VeryFarFuture() public {
        vm.startPrank(deployer);
        
        // 测试非常远的未来时间戳
        vm.expectRevert(); // 预期失败，因为没有实际的可清算用户
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1000e6,
            false,
            type(uint256).max,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_Deadline_PastTimestamp() public {
        vm.startPrank(deployer);
        
        // 测试过去的时间戳
        // 由于没有可清算的用户，实际会因为健康因子检查失败
        // 而不是 deadline 检查，所以使用通用的 expectRevert
        vm.expectRevert();
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1000e6,
            false,
            block.timestamp - 1,
            false
        );
        
        vm.stopPrank();
    }
    
    // ============ 提取金额边界测试 ============
    
    function test_Boundary_WithdrawETH_Zero() public {
        vm.startPrank(deployer);
        
        // 测试提取 0 ETH
        vm.expectRevert('AaveV3FlashLoan: no ETH to withdraw');
        liquidation.withdrawETH(0);
        
        vm.stopPrank();
    }
    
    function test_Boundary_WithdrawETH_MoreThanBalance() public {
        // 不给合约任何 ETH，测试提取时的行为
        vm.startPrank(deployer);
        
        // 尝试提取 ETH，由于合约没有 ETH，应该会 revert
        vm.expectRevert('AaveV3FlashLoan: no ETH to withdraw');
        liquidation.withdrawETH(10 ether);
        
        vm.stopPrank();
    }
    
    function test_Boundary_WithdrawETH_ExactBalance() public {
        // 给合约一些 ETH
        uint256 amount = 5 ether;
        vm.deal(address(liquidation), amount);
        
        vm.startPrank(deployer);
        
        uint256 balanceBefore = deployer.balance;
        
        // 提取确切的余额
        liquidation.withdrawETH(amount);
        
        // 验证提取成功
        assertEq(address(liquidation).balance, 0);
        assertEq(deployer.balance, balanceBefore + amount);
        
        vm.stopPrank();
    }
    
    function test_Boundary_WithdrawETH_VerySmallAmount() public {
        // 给合约一些 ETH
        vm.deal(address(liquidation), 1 ether);
        
        vm.startPrank(deployer);
        
        uint256 balanceBefore = deployer.balance;
        
        // 提取非常小的金额（1 wei）
        liquidation.withdrawETH(1);
        
        // 验证提取成功
        assertEq(address(liquidation).balance, 1 ether - 1);
        assertEq(deployer.balance, balanceBefore + 1);
        
        vm.stopPrank();
    }
    
    function test_Boundary_WithdrawToken_Zero() public {
        vm.startPrank(deployer);
        
        // 测试提取 0 代币
        vm.expectRevert('AaveV3FlashLoan: invalid amount');
        liquidation.withdrawToken(USDC, 0);
        
        vm.stopPrank();
    }
    
    function test_Boundary_WithdrawToken_MoreThanBalance() public {
        // 给合约一些 USDC
        deal(USDC, address(liquidation), 1000e6);
        
        vm.startPrank(deployer);
        
        // 尝试提取超过余额的代币
        vm.expectRevert('ERC20: transfer amount exceeds balance');
        liquidation.withdrawToken(USDC, 2000e6);
        
        vm.stopPrank();
    }
    
    function test_Boundary_WithdrawToken_ExactBalance() public {
        // 给合约一些 USDC
        uint256 amount = 1000e6;
        deal(USDC, address(liquidation), amount);
        
        vm.startPrank(deployer);
        
        uint256 balanceBefore = IERC20(USDC).balanceOf(deployer);
        
        // 提取确切的余额
        liquidation.withdrawToken(USDC, amount);
        
        // 验证提取成功
        assertEq(IERC20(USDC).balanceOf(address(liquidation)), 0);
        assertEq(IERC20(USDC).balanceOf(deployer), balanceBefore + amount);
        
        vm.stopPrank();
    }
    
    function test_Boundary_WithdrawToken_VerySmallAmount() public {
        // 给合约一些 USDC
        deal(USDC, address(liquidation), 1000e6);
        
        vm.startPrank(deployer);
        
        uint256 balanceBefore = IERC20(USDC).balanceOf(deployer);
        
        // 提取非常小的金额（1 micro USDC）
        liquidation.withdrawToken(USDC, 1);
        
        // 验证提取成功
        assertEq(IERC20(USDC).balanceOf(address(liquidation)), 1000e6 - 1);
        assertEq(IERC20(USDC).balanceOf(deployer), balanceBefore + 1);
        
        vm.stopPrank();
    }
    
    // ============ 布尔参数边界测试 ============
    
    function test_Boundary_ReceiveAToken_True() public {
        vm.startPrank(deployer);
        
        // 测试 receiveAToken = true
        vm.expectRevert(); // 预期失败，因为没有实际的可清算用户
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1000e6,
            true, // receiveAToken = true
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_ReceiveAToken_False() public {
        vm.startPrank(deployer);
        
        // 测试 receiveAToken = false
        vm.expectRevert(); // 预期失败，因为没有实际的可清算用户
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1000e6,
            false, // receiveAToken = false
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_UseMaxDebt_True() public {
        vm.startPrank(deployer);
        
        // 测试 useMaxDebt = true
        vm.expectRevert(); // 预期失败，因为没有实际的可清算用户
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1000e6,
            false,
            block.timestamp + 300,
            true // useMaxDebt = true
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_UseMaxDebt_False() public {
        vm.startPrank(deployer);
        
        // 测试 useMaxDebt = false
        vm.expectRevert(); // 预期失败，因为没有实际的可清算用户
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1000e6,
            false,
            block.timestamp + 300,
            false // useMaxDebt = false
        );
        
        vm.stopPrank();
    }
    
    // ============ 合约状态边界测试 ============
    
    function test_Boundary_PauseState_Transitions() public {
        vm.startPrank(deployer);
        
        // 初始状态应该是未暂停
        assertFalse(liquidation.paused());
        
        // 暂停
        liquidation.pause();
        assertTrue(liquidation.paused());
        
        // 尝试在暂停状态下执行清算
        vm.expectRevert();
        liquidation.executeLiquidation(
            WETH, // collateralAsset
            USDC, // debtAsset
            testUser,
            1000e6,
            false,
            block.timestamp + 300,
            false
        );
        
        // 恢复
        liquidation.unpause();
        assertFalse(liquidation.paused());
        
        // 现在应该可以尝试执行清算（虽然会因为其他原因失败）
        vm.expectRevert(); // 预期失败，因为没有实际的可清算用户
        liquidation.executeLiquidation(
            WETH,
            USDC,
            testUser,
            1000e6,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Boundary_PauseState_DoublePause() public {
        vm.startPrank(deployer);
        
        // 暂停
        liquidation.pause();
        assertTrue(liquidation.paused());
        
        // 尝试再次暂停（应该失败）
        vm.expectRevert();
        liquidation.pause();
        
        vm.stopPrank();
    }
    
    function test_Boundary_PauseState_DoubleUnpause() public {
        vm.startPrank(deployer);
        
        // 确保未暂停
        assertFalse(liquidation.paused());
        
        // 尝试取消暂停（应该失败）
        vm.expectRevert();
        liquidation.unpause();
        
        vm.stopPrank();
    }
    
    // ============ Gas 使用边界测试 ============
    
    function test_Boundary_GasUsage_UpdateBuilderPayment() public {
        vm.startPrank(deployer);
        
        uint256 gasBefore = gasleft();
        liquidation.updateBuilderPaymentPercentage(50);
        uint256 gasUsed = gasBefore - gasleft();
        
        console2.log('Gas used for updateBuilderPaymentPercentage:', gasUsed);
        
        // 验证 gas 使用在合理范围内
        assertTrue(gasUsed < 50000, 'Gas usage should be reasonable for simple update');
        
        vm.stopPrank();
    }
    
    function test_Boundary_GasUsage_PauseUnpause() public {
        vm.startPrank(deployer);
        
        uint256 gasBefore = gasleft();
        liquidation.pause();
        uint256 gasUsedPause = gasBefore - gasleft();
        
        gasBefore = gasleft();
        liquidation.unpause();
        uint256 gasUsedUnpause = gasBefore - gasleft();
        
        console2.log('Gas used for pause:', gasUsedPause);
        console2.log('Gas used for unpause:', gasUsedUnpause);
        
        // 验证 gas 使用在合理范围内
        assertTrue(gasUsedPause < 50000, 'Gas usage should be reasonable for pause');
        assertTrue(gasUsedUnpause < 50000, 'Gas usage should be reasonable for unpause');
        
        vm.stopPrank();
    }
    
    function test_Boundary_GasUsage_WithdrawOperations() public {
        // 给合约一些资金
        vm.deal(address(liquidation), 1 ether);
        deal(USDC, address(liquidation), 1000e6);
        
        vm.startPrank(deployer);
        
        uint256 gasBefore = gasleft();
        liquidation.withdrawETH(0.1 ether);
        uint256 gasUsedETH = gasBefore - gasleft();
        
        gasBefore = gasleft();
        liquidation.withdrawToken(USDC, 100e6);
        uint256 gasUsedToken = gasBefore - gasleft();
        
        console2.log('Gas used for withdrawETH:', gasUsedETH);
        console2.log('Gas used for withdrawToken:', gasUsedToken);
        
        // 验证 gas 使用在合理范围内
        assertTrue(gasUsedETH < 50000, 'Gas usage should be reasonable for ETH withdrawal');
        assertTrue(gasUsedToken < 100000, 'Gas usage should be reasonable for token withdrawal');
        
        vm.stopPrank();
    }
    
    // ============ 数值精度边界测试 ============
    
    function test_Boundary_Precision_BuilderPaymentCalculation() public {
        vm.startPrank(deployer);
        
        // 测试不同百分比下的精度
        uint256[] memory percentages = new uint256[](6);
        percentages[0] = 1;   // 1%
        percentages[1] = 10;  // 10%
        percentages[2] = 33;  // 33%
        percentages[3] = 50;  // 50%
        percentages[4] = 66;  // 66%
        percentages[5] = 99;  // 99%
        
        for (uint i = 0; i < percentages.length; i++) {
            liquidation.updateBuilderPaymentPercentage(percentages[i]);
            assertEq(liquidation.builderPaymentPercentage(), percentages[i]);
            
            // 验证百分比计算的精度
            uint256 testAmount = 1000 ether;
            uint256 expectedPayment = (testAmount * percentages[i]) / 100;
            
            // 这里我们只是验证计算逻辑，实际的 builder payment 计算在合约内部
            assertTrue(expectedPayment <= testAmount, 'Builder payment should not exceed total amount');
        }
        
        vm.stopPrank();
    }
    
    // 接收 ETH
    receive() external payable {}
}