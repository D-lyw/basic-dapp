// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
// import {Permit2} from "permit2/src/Permit2.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

contract MockMarket {
    IPermit2 public immutable permit2;

    constructor(address _permit2) {
        permit2 = IPermit2(_permit2);
    }

    function depositERC20ByPermit(
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature
    ) public {
        permit2.permit(msg.sender, permitSingle, signature);
        permit2.transferFrom(
            msg.sender,
            address(this),
            permitSingle.details.amount,
            permitSingle.details.token
        );
    }

    function depositERC20ByApprove(address token, uint160 amount) public {
        // 2. transfer token from msg.sender to this contract
        permit2.transferFrom(msg.sender, address(this), amount, token);
    }

    function depositERC20ByPermitTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) public {
        permit2.permitTransferFrom(
            permit,
            transferDetails,
            msg.sender,
            signature
        );
    }
}
