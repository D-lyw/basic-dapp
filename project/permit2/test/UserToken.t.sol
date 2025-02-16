// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {MockToken} from "../src/MockToken.sol";

contract UserTokenTest is Test {
    MockToken public token;

    function setUp() public {
        token = new MockToken();
    }

    function testBalance() public view {
        assertEq(token.balanceOf(address(this)), 1000000 * 10 ** token.decimals());
    }

    // approve token to another address
    function testApprove() public {
        token.approve(address(this), 1000);
        assertEq(token.allowance(address(this), address(this)), 1000);
    }

}