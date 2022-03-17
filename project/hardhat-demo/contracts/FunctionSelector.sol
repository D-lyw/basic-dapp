// SPDX-License-Identifier: MIT

contract FunctionSelector {

  function getFunctionSelector(string memory _func) public pure returns (bytes4) {
    return bytes4(keccak256(bytes(_func)));
  }

  function returnCallData(uint j, uint i) public pure returns (bytes memory, bytes memory) {
    bytes memory sig = abi.encodeWithSignature("returnCallData(uint256,uint256)", j, i);
    return (msg.data, sig);
  }

}