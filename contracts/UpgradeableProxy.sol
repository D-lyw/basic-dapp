
pragma solidity ^0.8.0 

contract UpgradeableProxy {
    address implementation;
    address admin;
    
    fallback() external payable {
        implementation.delegatecall.value(msg.value)(msg.data);
    }
    
    function upgrade(address newImplementation) external {
        require(msg.sender == admin);
        implementation = newImplementation;
    }
}