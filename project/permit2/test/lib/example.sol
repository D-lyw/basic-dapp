// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignatureTransfer} from "./lib/permit2/src/SignatureTransfer.sol";
import {ISignatureTransfer} from "./lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {EIP712} from "./lib/permit2/src/EIP712.sol";
import {IAllowanceTransfer} from "./lib/permit2/src/interfaces/IAllowanceTransfer.sol";

contract Example {
    using SafeCast for uint256;
    
    function convertToUint48(uint256 value) public pure returns (uint48) {
        require(value <= type(uint48).max, "Value exceeds uint48 max");
        return uint48(value & ((1 << 48) - 1));
    }
}

contract PermitExample {
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );
    
    function getPermitSignature(
        address owner,
        address token,
        address spender,
        uint160 amount,
        uint48 expiration,
        uint48 nonce,
        uint256 sigDeadline,
        uint256 signerPrivateKey,
        bytes32 DOMAIN_SEPARATOR
    ) public pure returns (bytes memory) {
        // 1. 构造 PermitSingle 数据
        IAllowanceTransfer.PermitSingle memory permit = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: amount,      // 授权数量
                expiration: expiration,  // 授权到期时间
                nonce: nonce        // 从 permit2 获取的 nonce
            }),
            spender: spender,
            sigDeadline: sigDeadline  // 签名的有效期
        });
        
        // 2. 计算 PermitDetails 的哈希
        bytes32 permitDetailsHash = keccak256(
            abi.encode(
                keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"),
                permit.details.token,
                permit.details.amount,
                permit.details.expiration,
                permit.details.nonce
            )
        );
        
        // 3. 计算消息哈希
        bytes32 msgHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                permitDetailsHash,
                permit.spender,
                permit.sigDeadline
            )
        );
        
        // 4. 计算最终要签名的消息哈希
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                msgHash
            )
        );
        
        // 5. 签名消息
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        
        // 6. 返回签名结果
        return abi.encodePacked(r, s, v);
    }
} 