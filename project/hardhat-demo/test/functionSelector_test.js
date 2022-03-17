require('@nomiclabs/hardhat-waffle')
const { ethers } = require('hardhat')
const { expect } = require("chai")


describe("Function Selector", () => {
  let functionCaller
  before(async () => {
    const FunctionSelector = await ethers.getContractFactory('FunctionSelector')
    functionCaller = await FunctionSelector.deploy()
  })

  it('GetSelector', async () => {
    const param1 = "transfer(address,uint256)"
    const param2 = "returnCallData(uint256,uint256)"
    console.log(await functionCaller.getFunctionSelector(param1))
    console.log(await functionCaller.getFunctionSelector(param2))
  })

  it('CallData', async () => {
    const calldata = await functionCaller.returnCallData(2, 123)
    console.log(calldata)
  })

})