// SPDX-License-Identifier:MIT
pragma solidity ^0.8.0;

contract Wallet {
    address payable owner;

    constructor() {
        owner = payable(msg.sender);
    }

    receive() external payable {}

    function withdraw(uint256 _amount) external {
        require(msg.sender == owner, "sender is not owner");
        owner.transfer(_amount);
    }

    function sendByAddressFunction(address payable _address, uint256 _amount) public {
      payable(_address).transfer(_amount);
    }
}
