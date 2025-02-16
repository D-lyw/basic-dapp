// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {Permit2} from "permit2/src/Permit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {MockToken} from "../src/MockToken.sol";
import {PermitHash} from "./lib/PermitHash.sol";

contract Permit2Test is Test {
    Permit2 public permit2;
    MockToken public token;
    address public user;
    uint256 public privateKey;
    uint48 public expires;
    bytes32 public domainSeparator;

    function setUp() public {
        permit2 = new Permit2();
        token = new MockToken();

        domainSeparator = permit2.DOMAIN_SEPARATOR();
        expires = uint48(block.timestamp + 1000);

        privateKey = 0x12341234;
        user = vm.addr(privateKey);
        token.transfer(user, 1000 * 10 ** 18);

        vm.prank(user);
        token.approve(address(permit2), type(uint256).max);
    }

    function testPermit() public {
        // 构造签名数据
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer
            .PermitSingle({
                details: IAllowanceTransfer.PermitDetails({
                    token: address(token),
                    amount: 1000,
                    expiration: uint48(block.timestamp + 1000),
                    nonce: 0
                }),
                spender: address(this),
                sigDeadline: block.timestamp + 1000
            });

        // 获取签名
        bytes memory sig = getPermitSignature(permitSingle);

        // 执行 permit
        permit2.permit(user, permitSingle, sig);

        // 验证授权结果
        (uint160 amount, uint48 expiration, uint48 nonce) = permit2.allowance(user, address(token), address(this));
        assertEq(amount, 1000);
        assertEq(expiration, uint48(block.timestamp + 1000));
        assertEq(nonce, 1);
    }

    function getPermitSignature(
        IAllowanceTransfer.PermitSingle memory permitSingle
    ) public view returns (bytes memory) {
        bytes32 permitHash = PermitHash.hash(permitSingle);

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, permitHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
