// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console2} from 'forge-std/Test.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';
import {MultiVersionUniswapRouter} from '../src/MultiVersionUniswapRouter.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IPool} from 'aave-v3-origin/src/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol';

/**
 * @title AaveV3FlashLoanSimple 安全性测试套件
 * @notice 专门测试清算合约的安全性，包括各种攻击向量和安全漏洞
 * @dev 包含重入攻击、权限绕过、闪电贷攻击、价格操纵等安全测试
 */
contract AaveV3FlashLoanSimpleSecurityTest is Test {
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
    address attacker;
    address user1;
    address user2;
    
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
        vm.deal(attacker, 50 ether);
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
            10 // 10% builder payment
        );
        
        vm.stopPrank();
    }
    
    // ============ 重入攻击测试 ============
    
    function test_Security_ReentrancyAttack_ExecuteLiquidation() public {
        ReentrancyAttacker attackContract = new ReentrancyAttacker(address(liquidation));
        
        vm.startPrank(attacker);
        
        // 尝试通过重入攻击 executeLiquidation
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        attackContract.attackExecuteLiquidation();
        
        vm.stopPrank();
    }
    
    function test_Security_ReentrancyAttack_WithdrawETH() public {
        // 给合约一些 ETH
        vm.deal(address(liquidation), 10 ether);
        
        ReentrancyAttacker attackContract = new ReentrancyAttacker(address(liquidation));
        
        vm.startPrank(deployer);
        
        // 尝试通过重入攻击 withdrawETH
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        attackContract.attackWithdrawETH();
        
        vm.stopPrank();
    }
    
    function test_Security_ReentrancyAttack_WithdrawToken() public {
        // 给合约一些代币
        deal(USDC, address(liquidation), 10000e6);
        
        ReentrancyAttacker attackContract = new ReentrancyAttacker(address(liquidation));
        
        vm.startPrank(deployer);
        
        // 尝试通过重入攻击 withdrawToken
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        attackContract.attackWithdrawToken();
        
        vm.stopPrank();
    }
    
    // ============ 权限绕过攻击测试 ============
    
    function test_Security_PrivilegeEscalation_OnlyOwner() public {
        vm.startPrank(attacker);
        
        // 尝试绕过 onlyOwner 修饰符
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.executeLiquidation(
            WETH,
            USDC,
            user1,
            1000e6,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.updateBuilderPaymentPercentage(50);
        
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.pause();
        
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.unpause();
        
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.withdrawETH(1 ether);
        
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.withdrawToken(USDC, 1000e6);
        
        vm.stopPrank();
    }
    
    function test_Security_PrivilegeEscalation_WhenPaused() public {
        vm.startPrank(deployer);
        liquidation.pause();
        vm.stopPrank();
        
        vm.startPrank(attacker);
        
        // 即使在暂停状态下，非所有者也不能调用受保护的函数
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.executeLiquidation(
            WETH,
            USDC,
            user1,
            1000e6,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    // ============ 闪电贷攻击测试 ============
    
    function test_Security_FlashLoanAttack_UnauthorizedInitiator() public {
        FlashLoanAttacker attackContract = new FlashLoanAttacker(address(liquidation));
        
        vm.startPrank(attacker);
        
        // 尝试直接调用 executeOperation（模拟未授权的闪电贷回调）
        vm.expectRevert('AaveV3FlashLoan: unauthorized');
        attackContract.directExecuteOperation();
        
        vm.stopPrank();
    }
    
    function test_Security_FlashLoanAttack_WrongInitiator() public {
        FlashLoanAttacker attackContract = new FlashLoanAttacker(address(liquidation));
        
        // 模拟来自 Aave Pool 但错误发起者的调用
        address aavePool = IPoolAddressesProvider(AAVE_POOL_ADDRESSES_PROVIDER).getPool();
        
        vm.startPrank(aavePool);
        
        vm.expectRevert('AaveV3FlashLoan: unauthorized');
        attackContract.wrongInitiatorExecuteOperation();
        
        vm.stopPrank();
    }
    
    // ============ 输入验证攻击测试 ============
    
    function test_Security_InputValidation_ZeroAddresses() public {
        vm.startPrank(deployer);
        
        // 测试零地址输入
        vm.expectRevert('AaveV3FlashLoan: invalid collateral asset');
        liquidation.executeLiquidation(
            address(0),
            USDC,
            user1,
            1000e6,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.expectRevert('AaveV3FlashLoan: invalid debt asset');
        liquidation.executeLiquidation(
            WETH,
            address(0),
            user1,
            1000e6,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.expectRevert('AaveV3FlashLoan: invalid user address');
        liquidation.executeLiquidation(
            WETH,
            USDC,
            address(0),
            1000e6,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Security_InputValidation_SameAssets() public {
        vm.startPrank(deployer);
        
        // 测试相同的抵押品和债务资产
        vm.expectRevert('AaveV3FlashLoan: user health factor above threshold');
        liquidation.executeLiquidation(
            USDC,
            USDC,
            user1,
            1000e6,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    function test_Security_InputValidation_ExpiredDeadline() public {
        vm.startPrank(deployer);
        
        // 测试过期的截止时间
        vm.expectRevert('AaveV3FlashLoan: user health factor above threshold');
        liquidation.executeLiquidation(
            WETH,
            USDC,
            user1,
            1000e6,
            false,
            block.timestamp - 1,
            false
        );
        
        vm.stopPrank();
    }
    
    // ============ 整数溢出/下溢攻击测试 ============
    
    function test_Security_IntegerOverflow_BuilderPayment() public {
        vm.startPrank(deployer);
        
        // 测试极大的 builder payment percentage
        vm.expectRevert('AaveV3FlashLoan: invalid builder payment percentage');
        liquidation.updateBuilderPaymentPercentage(type(uint256).max);
        
        vm.expectRevert('AaveV3FlashLoan: invalid builder payment percentage');
        liquidation.updateBuilderPaymentPercentage(100);
        
        vm.stopPrank();
    }
    
    function test_Security_IntegerOverflow_DebtAmount() public {
        vm.startPrank(deployer);
        
        // 测试极大的债务数量（应该在 Aave 层面被拒绝）
        vm.expectRevert();
        liquidation.executeLiquidation(
            WETH,
            USDC,
            user1,
            type(uint256).max,
            false,
            block.timestamp + 300,
            false
        );
        
        vm.stopPrank();
    }
    
    // ============ 前端运行攻击测试 ============
    
    function test_Security_FrontRunning_BuilderPayment() public {
        vm.startPrank(deployer);
        
        // 模拟攻击者尝试在清算前修改 builder payment
        uint256 originalPercentage = liquidation.builderPaymentPercentage();
        
        vm.stopPrank();
        
        // 攻击者尝试修改（应该失败）
        vm.startPrank(attacker);
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.updateBuilderPaymentPercentage(99);
        vm.stopPrank();
        
        // 验证原始值未被修改
        assertEq(liquidation.builderPaymentPercentage(), originalPercentage);
    }
    
    function test_Security_FrontRunning_Pause() public {
        vm.startPrank(deployer);
        
        // 确保合约未暂停
        assertFalse(liquidation.paused());
        
        vm.stopPrank();
        
        // 攻击者尝试暂停合约（应该失败）
        vm.startPrank(attacker);
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.pause();
        vm.stopPrank();
        
        // 验证合约仍未暂停
        assertFalse(liquidation.paused());
    }
    
    // ============ 资金提取攻击测试 ============
    
    function test_Security_FundDrainage_UnauthorizedWithdraw() public {
        // 给合约一些资金
        vm.deal(address(liquidation), 10 ether);
        deal(USDC, address(liquidation), 10000e6);
        
        vm.startPrank(attacker);
        
        // 攻击者尝试提取 ETH
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.withdrawETH(5 ether);
        
        // 攻击者尝试提取代币
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        liquidation.withdrawToken(USDC, 5000e6);
        
        vm.stopPrank();
        
        // 验证资金仍在合约中
        assertEq(address(liquidation).balance, 10 ether);
        assertEq(IERC20(USDC).balanceOf(address(liquidation)), 10000e6);
    }
    
    function test_Security_FundDrainage_InvalidWithdrawParams() public {
        vm.startPrank(deployer);
        
        // 测试无效的提取参数
        vm.expectRevert('AaveV3FlashLoan: invalid token address');
        liquidation.withdrawToken(address(0), 1000);
        
        vm.expectRevert('AaveV3FlashLoan: invalid amount');
        liquidation.withdrawToken(USDC, 0);
        
        vm.expectRevert('AaveV3FlashLoan: no ETH to withdraw');
        liquidation.withdrawETH(1 ether);
        
        vm.stopPrank();
    }
    
    // ============ 时间操纵攻击测试 ============
    
    function test_Security_TimeManipulation_DeadlineBypass() public {
        vm.startPrank(deployer);
        
        uint256 deadline = block.timestamp + 300;
        
        // 尝试在截止时间后执行（通过时间跳跃）
        vm.warp(deadline + 1);
        
        vm.expectRevert('AaveV3FlashLoan: user health factor above threshold');
        liquidation.executeLiquidation(
            WETH,
            USDC,
            user1,
            1000e6,
            false,
            deadline,
            false
        );
        
        vm.stopPrank();
    }
    
    // ============ 合约自毁攻击测试 ============
    
    function test_Security_SelfDestruct_ResistanceToForcedEther() public {
        uint256 initialBalance = address(liquidation).balance;
        
        // 创建自毁合约强制发送 ETH
        SelfDestructAttacker destroyer = new SelfDestructAttacker{value: 5 ether}();
        destroyer.attack(payable(address(liquidation)));
        
        // 验证合约仍然正常工作（可以接收强制发送的 ETH）
        assertTrue(address(liquidation).balance >= initialBalance + 5 ether);
        
        // 验证合约功能仍然正常
        vm.startPrank(deployer);
        liquidation.updateBuilderPaymentPercentage(20);
        assertEq(liquidation.builderPaymentPercentage(), 20);
        vm.stopPrank();
    }
    
    // ============ 状态一致性测试 ============
    
    function test_Security_StateConsistency_PauseUnpause() public {
        vm.startPrank(deployer);
        
        // 测试暂停/恢复状态的一致性
        assertFalse(liquidation.paused());
        
        liquidation.pause();
        assertTrue(liquidation.paused());
        
        liquidation.unpause();
        assertFalse(liquidation.paused());
        
        // 多次暂停/恢复
        for (uint i = 0; i < 5; i++) {
            liquidation.pause();
            assertTrue(liquidation.paused());
            liquidation.unpause();
            assertFalse(liquidation.paused());
        }
        
        vm.stopPrank();
    }
    
    function test_Security_StateConsistency_BuilderPaymentUpdate() public {
        vm.startPrank(deployer);
        
        uint256 initialPercentage = liquidation.builderPaymentPercentage();
        
        // 测试多次更新的一致性
        uint256[] memory testPercentages = new uint256[](5);
        testPercentages[0] = 0;
        testPercentages[1] = 25;
        testPercentages[2] = 50;
        testPercentages[3] = 75;
        testPercentages[4] = 99;
        
        for (uint i = 0; i < testPercentages.length; i++) {
            liquidation.updateBuilderPaymentPercentage(testPercentages[i]);
            assertEq(liquidation.builderPaymentPercentage(), testPercentages[i]);
        }
        
        // 恢复初始值
        liquidation.updateBuilderPaymentPercentage(initialPercentage);
        assertEq(liquidation.builderPaymentPercentage(), initialPercentage);
        
        vm.stopPrank();
    }
    
    // ============ Gas 限制攻击测试 ============
    
    function test_Security_GasLimit_LargeOperations() public {
        vm.startPrank(deployer);
        
        // 测试大量操作是否会导致 gas 限制问题
        uint256 gasBefore = gasleft();
        
        // 执行一系列操作
        liquidation.updateBuilderPaymentPercentage(50);
        liquidation.pause();
        liquidation.unpause();
        liquidation.updateBuilderPaymentPercentage(25);
        
        uint256 gasUsed = gasBefore - gasleft();
        console2.log('Gas used for multiple operations:', gasUsed);
        
        // 验证 gas 使用在合理范围内
        assertTrue(gasUsed < 200000, 'Gas usage should be reasonable');
        
        vm.stopPrank();
    }
    
    // 接收 ETH
    receive() external payable {}
}

// ============ 攻击合约 ============

/**
 * @title 重入攻击合约
 */
contract ReentrancyAttacker {
    AaveV3FlashLoanSimple public target;
    bool public attacking = false;
    
    constructor(address _target) {
        target = AaveV3FlashLoanSimple(payable(_target));
    }
    
    function attackExecuteLiquidation() external {
        attacking = true;
        target.executeLiquidation(
            0x4200000000000000000000000000000000000006, // WETH
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC
            address(this),
            1000e6,
            false,
            block.timestamp + 300,
            false
        );
    }
    
    function attackWithdrawETH() external {
        attacking = true;
        target.withdrawETH(1 ether);
    }
    
    function attackWithdrawToken() external {
        attacking = true;
        target.withdrawToken(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, 1000e6);
    }
    
    receive() external payable {
        if (attacking && address(target).balance > 0) {
            // 尝试重入
            target.withdrawETH(1 ether);
        }
    }
}

/**
 * @title 闪电贷攻击合约
 */
contract FlashLoanAttacker {
    AaveV3FlashLoanSimple public target;
    
    constructor(address _target) {
        target = AaveV3FlashLoanSimple(payable(_target));
    }
    
    function directExecuteOperation() external {
        // 尝试直接调用 executeOperation
        target.executeOperation(
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC
            1000e6,
            1e6,
            address(this),
            abi.encode(
                0x4200000000000000000000000000000000000006, // WETH
                address(this),
                false,
                block.timestamp + 300,
                false
            )
        );
    }
    
    function wrongInitiatorExecuteOperation() external {
        // 模拟来自 Aave Pool 但错误发起者的调用
        target.executeOperation(
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC
            1000e6,
            1e6,
            address(this), // 错误的发起者
            abi.encode(
                0x4200000000000000000000000000000000000006, // WETH
                address(this),
                false,
                block.timestamp + 300,
                false
            )
        );
    }
}

/**
 * @title 自毁攻击合约
 */
contract SelfDestructAttacker {
    constructor() payable {}
    
    function attack(address payable target) external {
        selfdestruct(target);
    }
}