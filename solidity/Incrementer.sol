pragma solidity ^0.8.0;

contract Incrementer {
    // global value
    uint256 public counter;
    
    event Increment(uint256 value);
    event Reset();
    
    constructor(uint256 initialValue) {
        counter = initialValue;
    }
    
    function increment(uint256 value) public {
        require(value > 0, "Increment value must be a positive number");
        counter += value;
        emit Increment(value);
    }
    
    function reset() public {
        counter = 0;
        emit Reset();
    }
    
    function getCounter() public view returns (uint256) {
        return counter;
    }
}