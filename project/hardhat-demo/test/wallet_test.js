require('@nomiclabs/hardhat-waffle')
const { expect } = require('chai')
const { ethers } = require('hardhat')
const { utils } = ethers

describe('Wallet', () => {
  let wallet
  let owner
  let addr1
  before(async () => {
    ;[owner, addr1] = await ethers.getSigners()
    const Wallet = await ethers.getContractFactory('Wallet')
    wallet = await Wallet.deploy()
  })

  it('Base', async () => {
    console.log(wallet.address)
    console.log(await ethers.provider.getBalance(wallet.address))
  })

  it('Send Ether', async () => {
    await addr1.sendTransaction({
      to: wallet.address,
      value: 20000,
    })
    expect(await ethers.provider.getBalance(wallet.address)).to.be.equal(20000)
    console.log('addr amount: ', utils.formatEther(await addr1.getBalance()))
    await wallet.withdraw(10000)
    expect(await ethers.provider.getBalance(wallet.address)).to.be.equal(10000)
  })

  it('Not owner withdraw', async () => {
    await expect(wallet.connect(addr1).withdraw()).to.be.reverted
  })
})
