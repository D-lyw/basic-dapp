// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // OpenZeppelin solidity compiler version is not compatible with permit2
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MTK", 18) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}


