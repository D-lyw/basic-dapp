// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from 'forge-std/Test.sol';
import {DeployScript} from '../script/Deploy.s.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';

contract DeployTest is Test {
    DeployScript public deployScript;
    AaveV3FlashLoanSimple public flashLoan;

    function setUp() public {
        deployScript = new DeployScript();
    }

    function test_DeployMainnet() public {
        vm.startPrank(msg.sender);
        deployScript.deployMainnet();
        vm.stopPrank();
    }

    function test_DeployBase() public {
        vm.startPrank(msg.sender);
        deployScript.deployBase();
        vm.stopPrank();
    }

    function test_Run() public {
        vm.startPrank(msg.sender);
        deployScript.run();
        vm.stopPrank();
    }
} 