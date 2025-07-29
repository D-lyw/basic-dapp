// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from 'forge-std/Test.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract AaveV3FlashLoanSimpleTest is Test {
    AaveV3FlashLoanSimple public liquidation;
    
    // 测试网络地址
    address constant ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant AGGREGATION_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 constant BUILDER_PAYMENT_PERCENTAGE = 60;

    function setUp() public {
        liquidation = new AaveV3FlashLoanSimple(
            ADDRESS_PROVIDER,
            AGGREGATION_ROUTER,
            WETH,
            BUILDER_PAYMENT_PERCENTAGE
        );
    }

    function test_Deployment() public {
        assertEq(address(liquidation.ADDRESSES_PROVIDER()), ADDRESS_PROVIDER);
        assertEq(liquidation.AGGREGATION_ROUTER(), AGGREGATION_ROUTER);
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
        assertEq(IERC20(testToken).balanceOf(address(this)), amount);
    }

    function test_WithdrawETH() public {
        // 给合约转一些 ETH
        vm.deal(address(liquidation), 1 ether);
        
        // 记录初始余额
        uint256 initialBalance = address(this).balance;
        
        // 提取 ETH
        liquidation.withdrawETH(0);
        
        // 检查 ETH 是否被正确提取
        assertEq(address(this).balance, initialBalance + 1 ether);
    }
}

// 用于测试的 Mock ERC20 代币
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    
    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
} 