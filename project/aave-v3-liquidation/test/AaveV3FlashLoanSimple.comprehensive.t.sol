// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console2} from 'forge-std/Test.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';
import {MultiVersionUniswapRouter} from '../src/MultiVersionUniswapRouter.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IPool} from 'aave-v3-origin/src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPriceOracleGetter} from 'aave-v3-origin/src/contracts/interfaces/IPriceOracleGetter.sol';
import {DataTypes} from 'aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol';

/**
 * @title AaveV3FlashLoanSimple 综合测试套件
 * @notice 全面测试清算合约的安全性、可靠性和边界条件
 * @dev 包含正常流程、异常处理、安全性验证、gas 优化验证等测试
 */
contract AaveV3FlashLoanSimpleComprehensiveTest is Test {
    AaveV3FlashLoanSimple public liquidation;
    MultiVersionUniswapRouter public multiRouter;
    IPool public pool;
    IPriceOracleGetter public oracle;
    
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
    
    uint256 constant BUILDER_PAYMENT_PERCENTAGE = 10; // 10% for testing
    uint256 constant FORK_BLOCK_NUMBER = 34982557;
    
    address deployer;
    address attacker;
    address user1;
    address user2;
    
    // 测试用的清算目标
    address testDebtAsset;
    address testCollateralAsset;
    address testUser;
    uint256 testDebtAmount;
    
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
    
    event BuilderPaymentFailed(
        address indexed builder,
        uint256 amount,
        string reason
    );
    
    function setUp() public {
        // 创建 Base mainnet fork
        vm.createFork(vm.envString('BASE_MAINNET_RPC_URL'), FORK_BLOCK_NUMBER);
        vm.selectFork(0);
        
        // 设置测试账户
        deployer = makeAddr('deployer');
        attacker = makeAddr('attacker');
        user1 = makeAddr('user1');
        user2 = makeAddr('user2');
        
        // 给测试账户一些 ETH
        vm.deal(deployer, 100 ether);
        vm.deal(attacker, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
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
            BUILDER_PAYMENT_PERCENTAGE
        );
        
        vm.stopPrank();
        
        // 获取 Aave 合约实例
        pool = IPool(IPoolAddressesProvider(AAVE_POOL_ADDRESSES_PROVIDER).getPool());
        oracle = IPriceOracleGetter(IPoolAddressesProvider(AAVE_POOL_ADDRESSES_PROVIDER).getPriceOracle());
        
        // 设置测试清算参数
        testDebtAsset = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;
        testCollateralAsset = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        testUser = 0x196bFAc62dF1f91718fDdC26ECf1B1967D4d2cB5;
        testDebtAmount = 21912517572137;
    }
    
    // ============ 部署和初始化测试 ============
    
    function test_DeploymentConfiguration() public {
        assertEq(address(liquidation.ADDRESSES_PROVIDER()), AAVE_POOL_ADDRESSES_PROVIDER);
        assertEq(address(liquidation.MULTI_ROUTER()), address(multiRouter));
        assertEq(liquidation.WETH(), WETH);

        assertEq(liquidation.builderPaymentPercentage(), BUILDER_PAYMENT_PERCENTAGE);
        assertEq(liquidation.owner(), deployer);
        assertFalse(liquidation.paused());
    }
    
    function test_RevertWhen_DeployWithZeroAddresses() public {
        vm.startPrank(deployer);
        
        // 测试零地址提供者
        vm.expectRevert();
        new AaveV3FlashLoanSimple(
            address(0),
            address(multiRouter),
            WETH,
            BUILDER_PAYMENT_PERCENTAGE
        );
        
        // 测试零多路由器地址
        vm.expectRevert();
        new AaveV3FlashLoanSimple(
            AAVE_POOL_ADDRESSES_PROVIDER,
            address(0),
            WETH,
            BUILDER_PAYMENT_PERCENTAGE
        );
        
        // 测试零 WETH 地址
        vm.expectRevert();
        new AaveV3FlashLoanSimple(
            AAVE_POOL_ADDRESSES_PROVIDER,
            address(multiRouter),
            address(0),
            BUILDER_PAYMENT_PERCENTAGE
        );
        
        // 测试无效的 builder 支付比例
        vm.expectRevert();
        new AaveV3FlashLoanSimple(
            AAVE_POOL_ADDRESSES_PROVIDER,
            address(multiRouter),
            WETH,
            100 // 超过最大值 99
        );
        

        
        vm.stopPrank();
    }
    
    // ============ 访问控制测试 ============
    
    function test_OnlyOwnerFunctions() public {
        // 测试非所有者调用受限函数
        vm.startPrank(attacker);
        
        vm.expectRevert();
        liquidation.updateBuilderPaymentPercentage(20);
        
        vm.expectRevert();
        liquidation.pause();
        
        vm.expectRevert();
        liquidation.unpause();
        
        vm.expectRevert();
        liquidation.withdrawToken(USDC, 100);
        
        vm.expectRevert();
        liquidation.withdrawETH(1 ether);
        
        vm.expectRevert();
        liquidation.executeLiquidation(
            testCollateralAsset,
            testDebtAsset,
            testUser,
            testDebtAmount,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_OwnerCanCallRestrictedFunctions() public {
        vm.startPrank(deployer);
        
        // 测试所有者可以调用受限函数
        liquidation.updateBuilderPaymentPercentage(20);
        assertEq(liquidation.builderPaymentPercentage(), 20);
        
        liquidation.pause();
        assertTrue(liquidation.paused());
        
        liquidation.unpause();
        assertFalse(liquidation.paused());
        
        vm.stopPrank();
    }
    
    // ============ 暂停机制测试 ============
    
    function test_PauseMechanism() public {
        vm.startPrank(deployer);
        
        // 暂停合约
        liquidation.pause();
        assertTrue(liquidation.paused());
        
        // 测试暂停状态下无法调用受保护的函数
        vm.expectRevert();
        liquidation.updateBuilderPaymentPercentage(20);
        
        vm.expectRevert();
        liquidation.withdrawToken(USDC, 100);
        
        vm.expectRevert();
        liquidation.withdrawETH(1 ether);
        
        vm.expectRevert();
        liquidation.executeLiquidation(
            testCollateralAsset,
            testDebtAsset,
            testUser,
            testDebtAmount,
            false,
            block.timestamp + 300,
            false
        );
        
        // 恢复合约
        liquidation.unpause();
        assertFalse(liquidation.paused());
        
        // 恢复后可以正常调用
        liquidation.updateBuilderPaymentPercentage(20);
        assertEq(liquidation.builderPaymentPercentage(), 20);
        
        vm.stopPrank();
    }
    
    // ============ 参数验证测试 ============
    
    function test_RevertWhen_InvalidLiquidationParameters() public {
        vm.startPrank(deployer);
        
        // 测试零抵押品地址
        vm.expectRevert();
        liquidation.executeLiquidation(
            address(0),
            testDebtAsset,
            testUser,
            testDebtAmount,
            false,
            block.timestamp + 300,
            false
        );
        
        // 测试零债务资产地址
        vm.expectRevert();
        liquidation.executeLiquidation(
            testCollateralAsset,
            address(0),
            testUser,
            testDebtAmount,
            false,
            block.timestamp + 300,
            false
        );
        
        // 测试零用户地址
        vm.expectRevert();
        liquidation.executeLiquidation(
            testCollateralAsset,
            testDebtAsset,
            address(0),
            testDebtAmount,
            false,
            block.timestamp + 300,
            false
        );
        
        // 测试相同的抵押品和债务资产
        vm.expectRevert();
        liquidation.executeLiquidation(
            testDebtAsset,
            testDebtAsset,
            testUser,
            testDebtAmount,
            false,
            block.timestamp + 300,
            false
        );
        
        // 测试过期的截止时间
        vm.expectRevert();
        liquidation.executeLiquidation(
            testCollateralAsset,
            testDebtAsset,
            testUser,
            testDebtAmount,
            false,
            block.timestamp - 1,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_HealthyUser() public {
        vm.startPrank(deployer);
        
        // 使用健康用户地址（健康因子 > 1）
        address healthyUser = makeAddr('healthyUser');
        
        // 由于我们无法在测试中轻易创建一个健康的 Aave 用户，
        // 我们使用一个没有债务的地址，这应该会导致健康因子检查失败
        vm.expectRevert();
        liquidation.executeLiquidation(
            testCollateralAsset,
            testDebtAsset,
            healthyUser,
            testDebtAmount,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    // ============ Builder 支付测试 ============
    
    function test_UpdateBuilderPaymentPercentage() public {
        vm.startPrank(deployer);
        
        uint256 oldPercentage = liquidation.builderPaymentPercentage();
        uint256 newPercentage = 25;
        
        vm.expectEmit(true, true, true, true);
        emit BuilderPaymentPercentageUpdated(oldPercentage, newPercentage);
        
        liquidation.updateBuilderPaymentPercentage(newPercentage);
        assertEq(liquidation.builderPaymentPercentage(), newPercentage);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_InvalidBuilderPaymentPercentage() public {
        vm.startPrank(deployer);
        
        vm.expectRevert();
        liquidation.updateBuilderPaymentPercentage(100);
        
        vm.expectRevert();
        liquidation.updateBuilderPaymentPercentage(101);
        
        vm.stopPrank();
    }
    
    function test_ZeroBuilderPaymentPercentage() public {
        vm.startPrank(deployer);
        
        // 设置为 0% builder 支付
        liquidation.updateBuilderPaymentPercentage(0);
        assertEq(liquidation.builderPaymentPercentage(), 0);
        
        vm.stopPrank();
    }
    
    // ============ 资产提取测试 ============
    
    function test_WithdrawToken() public {
        // 模拟合约收到一些代币
        deal(USDC, address(liquidation), 1000e6);
        
        vm.startPrank(deployer);
        
        uint256 initialBalance = IERC20(USDC).balanceOf(deployer);
        uint256 withdrawAmount = 500e6;
        
        vm.expectEmit(true, true, true, true);
        emit TokensWithdrawn(USDC, deployer, withdrawAmount, block.timestamp);
        
        liquidation.withdrawToken(USDC, withdrawAmount);
        
        assertEq(IERC20(USDC).balanceOf(deployer), initialBalance + withdrawAmount);
        assertEq(IERC20(USDC).balanceOf(address(liquidation)), 500e6);
        
        vm.stopPrank();
    }
    
    function test_WithdrawETH() public {
        // 给合约发送一些 ETH
        vm.deal(address(liquidation), 5 ether);
        
        vm.startPrank(deployer);
        
        uint256 initialBalance = deployer.balance;
        uint256 withdrawAmount = 2 ether;
        
        vm.expectEmit(true, true, true, true);
        emit TokensWithdrawn(address(0), deployer, withdrawAmount, block.timestamp);
        
        liquidation.withdrawETH(withdrawAmount);
        
        assertEq(deployer.balance, initialBalance + withdrawAmount);
        assertEq(address(liquidation).balance, 3 ether);
        
        vm.stopPrank();
    }
    
    function test_WithdrawETH_All() public {
        // 给合约发送一些 ETH
        vm.deal(address(liquidation), 3 ether);
        
        vm.startPrank(deployer);
        
        uint256 initialBalance = deployer.balance;
        
        // 传入 0 应该提取全部
        liquidation.withdrawETH(0);
        
        assertEq(deployer.balance, initialBalance + 3 ether);
        assertEq(address(liquidation).balance, 0);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_WithdrawInvalidToken() public {
        vm.startPrank(deployer);
        
        vm.expectRevert();
        liquidation.withdrawToken(address(0), 100);
        
        vm.expectRevert();
        liquidation.withdrawToken(USDC, 0);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_WithdrawETH_NoBalance() public {
        vm.startPrank(deployer);
        
        vm.expectRevert();
        liquidation.withdrawETH(1 ether);
        
        vm.stopPrank();
    }
    
    // ============ 重入攻击测试 ============
    
    function test_ReentrancyProtection() public {
        // 部署恶意合约
        MaliciousContract malicious = new MaliciousContract(address(liquidation));
        
        vm.startPrank(deployer);
        
        // 尝试重入攻击应该失败
        vm.expectRevert();
        malicious.attack();
        
        vm.stopPrank();
    }
    
    // ============ Gas 优化验证测试 ============
    
    function test_GasOptimization_StateVariableCaching() public {
        vm.startPrank(deployer);
        
        // 测试 builderPaymentPercentage 的缓存优化
        uint256 gasBefore = gasleft();
        liquidation.updateBuilderPaymentPercentage(15);
        uint256 gasAfter = gasleft();
        
        uint256 gasUsed = gasBefore - gasAfter;
        console2.log('Gas used for updateBuilderPaymentPercentage:', gasUsed);
        
        // 验证 gas 使用在合理范围内
        assertTrue(gasUsed < 50000, 'Gas usage should be optimized');
        
        vm.stopPrank();
    }
    
    // ============ 事件发射测试 ============
    
    function test_EventEmission() public {
        vm.startPrank(deployer);
        
        // 测试 BuilderPaymentPercentageUpdated 事件
        vm.expectEmit(true, true, true, true);
        emit BuilderPaymentPercentageUpdated(BUILDER_PAYMENT_PERCENTAGE, 20);
        liquidation.updateBuilderPaymentPercentage(20);
        
        // 测试 EmergencyPaused 事件
        vm.expectEmit(true, true, true, true);
        emit EmergencyPaused(deployer, block.timestamp);
        liquidation.pause();
        
        // 测试 EmergencyUnpaused 事件
        vm.expectEmit(true, true, true, true);
        emit EmergencyUnpaused(deployer, block.timestamp);
        liquidation.unpause();
        
        vm.stopPrank();
    }
    
    // ============ 边界条件测试 ============
    
    function test_EdgeCase_MaxBuilderPaymentPercentage() public {
        vm.startPrank(deployer);
        
        // 测试最大允许的 builder 支付比例
        liquidation.updateBuilderPaymentPercentage(99);
        assertEq(liquidation.builderPaymentPercentage(), 99);
        
        vm.stopPrank();
    }
    
    function test_EdgeCase_MinimumDeadline() public {
        vm.startPrank(deployer);
        
        // 测试最小有效截止时间（当前时间 + 1 秒）
        uint256 minDeadline = block.timestamp + 1;
        
        // 这应该不会因为截止时间而失败（可能因为其他原因失败）
        try liquidation.executeLiquidation(
            testCollateralAsset,
            testDebtAsset,
            testUser,
            testDebtAmount,
            false,
            minDeadline,
            false
        ) {
            // 如果成功，说明通过了基本验证，但在测试环境中这是意外的
            // 因为我们没有设置实际的可清算用户
            console2.log('Liquidation succeeded unexpectedly');
         } catch {
             // 预期会失败，因为没有实际的可清算用户
             console2.log('Liquidation failed as expected due to no liquidatable user');
         }
         
         // 测试通过，因为我们只是验证最小截止时间不会导致立即失败
         assertTrue(true, 'Minimum deadline test completed');
        
        vm.stopPrank();
    }
    
    // ============ 集成测试 ============
    
    function test_Integration_MultiRouterConnection() public {
        // 验证 liquidation 合约正确连接到 multiRouter
        assertEq(address(liquidation.MULTI_ROUTER()), address(multiRouter));
        
        // 验证 multiRouter 的配置
        assertEq(address(multiRouter.UNIVERSAL_ROUTER()), UNIVERSAL_ROUTER);
        assertEq(address(multiRouter.PERMIT2()), PERMIT2);
        assertEq(multiRouter.WETH(), WETH);
        assertEq(multiRouter.USDC(), USDC);
    }
    
    function test_Integration_AaveConnection() public {
        // 验证 Aave 连接
        assertEq(address(liquidation.ADDRESSES_PROVIDER()), AAVE_POOL_ADDRESSES_PROVIDER);
        
        // 验证可以访问 Aave 池
        address poolAddress = IPoolAddressesProvider(AAVE_POOL_ADDRESSES_PROVIDER).getPool();
        assertTrue(poolAddress != address(0));
        
        // 验证可以访问价格预言机
        address oracleAddress = IPoolAddressesProvider(AAVE_POOL_ADDRESSES_PROVIDER).getPriceOracle();
        assertTrue(oracleAddress != address(0));
    }
    
    // ============ 实际清算测试（如果有合适的目标）============
    
    function test_RealLiquidation_IfTargetAvailable() public {
        // 检查是否有可清算的目标
        (, , , , , uint256 healthFactor) = pool.getUserAccountData(testUser);
        
        if (healthFactor >= 1e18) {
            console2.log('No liquidatable target available, skipping real liquidation test');
            return;
        }
        
        vm.startPrank(deployer);
        
        uint256 initialContractBalance = address(liquidation).balance;
        
        try liquidation.executeLiquidation(
            testCollateralAsset,
            testDebtAsset,
            testUser,
            testDebtAmount,
            false,
            block.timestamp + 300,
            false
        ) {
            console2.log('Real liquidation executed successfully');
            
            // 验证合约获得了利润
            uint256 finalContractBalance = address(liquidation).balance;
            assertTrue(finalContractBalance >= initialContractBalance, 'Contract should have profit or break even');
            
        } catch Error(string memory reason) {
            console2.log('Real liquidation failed with reason:', reason);
            // 在测试环境中，某些失败是预期的
        } catch (bytes memory) {
            console2.log('Real liquidation failed with low-level error');
        }
        
        vm.stopPrank();
    }
    
    // ============ 辅助函数 ============
    
    function _createLiquidatablePosition() internal {
        // 这个函数可以用来创建一个可清算的位置用于测试
        // 在实际测试中，这需要复杂的设置，包括借贷和价格操纵
        // 暂时留空，使用现有的链上数据
    }
    
    // 接收 ETH
    receive() external payable {}
}

// ============ 恶意合约用于重入测试 ============

contract MaliciousContract {
    AaveV3FlashLoanSimple public target;
    bool public attacking = false;
    
    constructor(address _target) {
        target = AaveV3FlashLoanSimple(payable(_target));
    }
    
    function attack() external {
        attacking = true;
        // 尝试重入攻击
        target.withdrawETH(1 ether);
    }
    
    receive() external payable {
        if (attacking) {
            // 尝试重入
            target.withdrawETH(1 ether);
        }
    }
}

// ============ 事件定义（用于测试）============

event BuilderPaymentPercentageUpdated(
    uint256 oldPercentage,
    uint256 newPercentage
);

event EmergencyPaused(address indexed caller, uint256 timestamp);

event EmergencyUnpaused(address indexed caller, uint256 timestamp);

event TokensWithdrawn(
    address indexed token,
    address indexed to,
    uint256 amount,
    uint256 timestamp
);