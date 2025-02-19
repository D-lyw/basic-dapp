// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {Permit2} from "permit2/src/Permit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {MockToken} from "../src/MockToken.sol";
import {MockMarket} from "../src/MockMarket.sol";
import {PermitHash} from "./lib/PermitHash.sol";

contract Permit2Test is Test {
    Permit2 public permit2;
    MockToken public token;
    MockMarket public market;
    address public user;
    uint256 public privateKey;
    uint48 public expires;
    bytes32 public domainSeparator;

    function setUp() public {
        permit2 = new Permit2();
        token = new MockToken();
        market = new MockMarket(address(permit2));

        domainSeparator = permit2.DOMAIN_SEPARATOR();
        expires = uint48(block.timestamp + 1000);

        privateKey = 0x12341234;
        user = vm.addr(privateKey);
        token.transfer(user, 100000 * 10 ** 18);

        vm.prank(user);
        token.approve(address(permit2), type(uint256).max);
    }

    /// @notice 测试 permit 授权
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

        // 执行 permit 授权
        permit2.permit(user, permitSingle, sig);

        // 验证授权结果
        (uint160 amount, uint48 expiration, uint48 nonce) = permit2.allowance(
            user,
            address(token),
            address(this)
        );
        assertEq(amount, 1000);
        assertEq(expiration, uint48(block.timestamp + 1000));
        assertEq(nonce, 1);
    }

    // 测试通过 permit 授权的方式转账
    function testTransferByPermit() public {
        assertEq(token.balanceOf(address(market)), 0);
        // 构造签名数据
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer
            .PermitSingle({
                details: IAllowanceTransfer.PermitDetails({
                    token: address(token),
                    amount: 200,
                    expiration: uint48(block.timestamp + 1000),
                    nonce: 0
                }),
                spender: address(market),
                sigDeadline: block.timestamp + 1000
            });

        // 获取签名
        bytes memory sig = getPermitSignature(permitSingle);

        vm.prank(user);
        market.depositERC20ByPermit(permitSingle, sig);

        assertEq(token.balanceOf(address(market)), 200);
        console.log("market balance: ", token.balanceOf(address(market)));
        console.log("user balance: ", token.balanceOf(user));
    }

    // 测试通过 approve 授权的方式转账
    function testTransferByApprove() public {
        // 1. approve token permission to permit2 by permit2.approve fuction
        vm.prank(user);
        permit2.approve(
            address(token),
            address(market),
            1000,
            uint48(block.timestamp + 1 hours)
        );
        vm.prank(user);
        market.depositERC20ByApprove(address(token), 1000);

        // (uint160 amount, uint48 expiration, uint48 nonce) = permit2.allowance(user, address(token), address(market));
        // assertEq(amount, 1000);
        // assertEq(expiration, uint48(block.timestamp + 1 hours));
        // assertEq(nonce, 0);
        assertEq(token.balanceOf(address(market)), 1000);
        console.log("market balance: ", token.balanceOf(address(market)));
    }

    // 测试通过 permitTransferFrom 授权的方式转账
    function testTransferByPermitTransferFrom() public {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer
            .PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(token),
                    amount: 1000
                }),
                nonce: 0,
                deadline: block.timestamp + 1000
            });
        bytes memory sig = getPermitTransferSignature(permit);

        vm.prank(user);
        market.depositERC20ByPermitTransferFrom(
            permit,
            ISignatureTransfer.SignatureTransferDetails({
                to: address(market),
                requestedAmount: 1000
            }),
            sig
        );

        assertEq(token.balanceOf(address(market)), 1000);
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

    function getPermitTransferSignature(
        ISignatureTransfer.PermitTransferFrom memory permit
    ) internal view returns (bytes memory sig) {
        bytes32 tokenPermissions = keccak256(
            abi.encode(PermitHash._TOKEN_PERMISSIONS_TYPEHASH, permit.permitted)
        );
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        PermitHash._PERMIT_TRANSFER_FROM_TYPEHASH,
                        tokenPermissions,
                        address(market),
                        permit.nonce,
                        permit.deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return abi.encodePacked(r, s, v);
    }
}
