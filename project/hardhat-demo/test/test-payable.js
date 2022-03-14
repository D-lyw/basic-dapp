require('@nomiclabs/hardhat-waffle')

const { expect } = require('chai')
const { ethers } = require('hardhat')
const { provider, utils } = ethers

describe('Payable', function () {
  let payable
  let owner
  let addr1

  before(async () => {
    ;[owner, addr1] = await ethers.getSigners()
    const Payable = await ethers.getContractFactory('Payable')
    payable = await Payable.deploy()

    await payable.deployed()
    console.log('Owner', owner.address)
    console.log('Contract', payable.address)
  })

  it('Deposit', async () => {
    await payable.deposit({ value: 1000000 })
    expect(await ethers.provider.getBalance(payable.address)).to.equal(1000000)
    await payable.deposit({ value: 2000000 })

    const balance = await provider.getBalance(payable.address)
    console.log(balance, utils.formatEther(balance))

    // await payable.transfer(addr1.address, 1000000)
    console.log(utils.formatEther(await provider.getBalance(addr1.address)))
    // expect(await provider.getBalance(addr1.address)).to.equal(1000000)
    await payable.withdraw()
    expect(await provider.getBalance(payable.address)).to.equal(0)
  })

  it('Cant recevie Ether', async () => {
    await expect(payable.notPayable({ value: 1000000 })).to.be.reverted
  })

  it('Owner', async () => {
    expect(await payable.owner()).to.equal(owner.address)
    console.log(await ethers.provider.getBlockNumber())
    // console.log(await provider.getBalance(''))
  })

  it('Transfer', async () => {
    // await payable.transfer(addr1.address, 1000000)
    // expect(await provider.getBalance(payable.address)).to.equal(2000000)
    // expect(await provider.getBalance(addr1.address)).to.equal(1000000)
    // console.log(utils.formatEther(ethers.BigNumber.from('4009650703300000000000000')))
    // console.log("Earned: ", utils.formatEther(ethers.BigNumber.from('2172852820639374965088211')))
    // console.log("1 year total reward: ", utils.formatEther(ethers.BigNumber.from('5918441661050100000000000000')))
    // console.log('get reward rate: ', utils.formatEther(ethers.BigNumber.from('190258751902587519025')))
    // console.log('---------------------')
    // console.log(utils.formatEther(ethers.BigNumber.from('10172132101300000000000000')))
    // console.log("Earned ", utils.formatEther(ethers.BigNumber.from('5205415747541391980593415')))
    // console.log("1 year total reward: ", utils.formatEther(ethers.BigNumber.from('14875924637429000000000000000')))
    // console.log('get reward rate: ', utils.formatEther(ethers.BigNumber.from('253678335870116692034')))
  })

  describe('Deposit Ether', () => {})
})
