// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20WETH is ERC20 {
    constructor() ERC20("Wrapped eth", "WETH") {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
