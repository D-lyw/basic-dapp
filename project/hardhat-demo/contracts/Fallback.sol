// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Fallback {
    event Log(uint256 gas);

    // Fallback function must be declared as external.
    fallback() external payable {
        // send / transfer (forwards 2300 gas to this fallback function)
        // call (forwards all of the gas)
        emit Log(gasleft());
    }

    // Helper function to check the balance of this contract
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}

contract SendToFallback {
    event Log(uint256 gas);

    function transferToFallback(address payable _to) public payable {
        _to.transfer(msg.value);
        emit Log(gasleft());
    }

    function callFallback(address payable _to) public payable {
        (bool sent, ) = _to.call{value: msg.value}("");
        require(sent, "Failed to send Ether");
    }

    fallback() external payable {}

    receive() external payable {}
}
