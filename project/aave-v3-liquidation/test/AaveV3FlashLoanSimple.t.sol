// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from 'forge-std/Test.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IPermit2} from '@uniswap/permit2/src/interfaces/IPermit2.sol';

contract AaveV3FlashLoanSimpleTest is Test {
    AaveV3FlashLoanSimple public liquidation;
    
    // 测试网络地址
    address constant ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant UNIVERSAL_ROUTER = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 constant BUILDER_PAYMENT_PERCENTAGE = 60;

    function setUp() public {
        liquidation = new AaveV3FlashLoanSimple(
            ADDRESS_PROVIDER,
            UNIVERSAL_ROUTER,
            PERMIT2,
            WETH,
            BUILDER_PAYMENT_PERCENTAGE
        );
    }

    function test_Deployment() public {
        assertEq(address(liquidation.ADDRESSES_PROVIDER()), ADDRESS_PROVIDER);
        assertEq(address(liquidation.UNIVERSAL_ROUTER()), UNIVERSAL_ROUTER);
        assertEq(address(liquidation.PERMIT2()), PERMIT2);
        assertEq(liquidation.WETH(), WETH);
        assertEq(liquidation.builderPaymentPercentage(), BUILDER_PAYMENT_PERCENTAGE);
    }

    function test_UpdateBuilderPaymentPercentage() public {
        uint256 newPercentage = 70;
        liquidation.updateBuilderPaymentPercentage(newPercentage);
        assertEq(liquidation.builderPaymentPercentage(), newPercentage);
    }

    function testFail_UpdateBuilderPaymentPercentage_NotOwner() public {
        vm.prank(address(1));
        liquidation.updateBuilderPaymentPercentage(70);
    }

    function testFail_UpdateBuilderPaymentPercentage_TooHigh() public {
        liquidation.updateBuilderPaymentPercentage(100);
    }

    function test_PauseAndUnpause() public {
        liquidation.pause();
        assertTrue(liquidation.paused());
        
        liquidation.unpause();
        assertFalse(liquidation.paused());
    }

    function testFail_Pause_NotOwner() public {
        vm.prank(address(1));
        liquidation.pause();
    }

    function testFail_Unpause_NotOwner() public {
        liquidation.pause();
        vm.prank(address(1));
        liquidation.unpause();
    }

    function test_WithdrawToken() public {
        // 部署一个测试代币
        address testToken = address(new MockERC20());
        uint256 amount = 1000;
        
        // 给合约转一些代币
        MockERC20(testToken).mint(address(liquidation), amount);
        
        // 提取代币
        liquidation.withdrawToken(testToken, amount);
        
        // 检查代币是否被正确提取
        assertEq(IERC20(testToken).balanceOf(liquidation.owner()), amount);
    }

    function test_ApproveTokenWithPermit2() public {
        // 部署一个测试代币
        address testToken = address(new MockERC20());
        uint160 amount = 1000;
        uint48 expiration = uint48(block.timestamp + 1 days);

        // 调用 approveTokenWithPermit2 函数
        liquidation.approveTokenWithPermit2(testToken, amount, expiration);

        // 验证 Permit2 的授权
        assertEq(
            IERC20(testToken).allowance(address(liquidation), PERMIT2),
            type(uint256).max
        );
    }

    function test_WithdrawETH() public {
        // 给合约转一些 ETH
        vm.deal(address(liquidation), 1 ether);
        
        // 记录初始余额
        uint256 initialBalance = address(this).balance;
        
        // 提取 ETH
        liquidation.withdrawETH(0);
        
        // 检查 ETH 是否被正确提取
        assertEq(liquidation.owner().balance, initialBalance + 1 ether);
    }

    function testFail_ApproveTokenWithPermit2_NotOwner() public {
        address testToken = address(new MockERC20());
        uint160 amount = 1000;
        uint48 expiration = uint48(block.timestamp + 1 days);

        // 使用非所有者地址调用 approveTokenWithPermit2
        vm.prank(address(1));
        liquidation.approveTokenWithPermit2(testToken, amount, expiration);
    }

    function testFail_ApproveTokenWithPermit2_ZeroAddress() public {
        uint160 amount = 1000;
        uint48 expiration = uint48(block.timestamp + 1 days);

        // 使用零地址调用 approveTokenWithPermit2
        liquidation.approveTokenWithPermit2(address(0), amount, expiration);
    }

    function testFail_ApproveTokenWithPermit2_WhenPaused() public {
        address testToken = address(new MockERC20());
        uint160 amount = 1000;
        uint48 expiration = uint48(block.timestamp + 1 days);

        // 暂停合约
        liquidation.pause();

        // 尝试在暂停状态下调用 approveTokenWithPermit2
        liquidation.approveTokenWithPermit2(testToken, amount, expiration);
    }
}

// 用于测试的 Mock ERC20 代币
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(allowance[from][msg.sender] >= amount, 'MockERC20: insufficient allowance');
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}