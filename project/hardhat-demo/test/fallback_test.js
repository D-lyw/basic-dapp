require('@nomiclabs/hardhat-waffle')
const { expect } = require('chai')
const { utils } = require('ethers')
const { ethers } = require('hardhat')
const { provider } = ethers

describe('Fallback', () => {
  let owner
  let addr1
  let fallback

  before(async () => {
    ;[owner, addr1] = await ethers.getSigners()
    const Fallback = await ethers.getContractFactory('Fallback')
    fallback = await Fallback.deploy()

    const Sender = await ethers.getContractFactory('SendToFallback')
    sender = await Sender.deploy()
  })

  it('Deployed', async () => {
    console.log(sender.address, fallback.address)
  })

  it('Sender Ether', async () => {
    await sender.transferToFallback(fallback.address)
    // console.log(await provider.getBalance(fallback.address))

    console.log(await provider.getBalance(fallback.address))
  })

  it('Call Fallback', async () => {
    await owner.sendTransaction({
      to: sender.address,
      value: utils.parseEther('1'),
    })
    console.log(utils.formatEther(await provider.getBalance(sender.address)))

    await sender.transferToFallback(fallback.address, {
      value: utils.parseEther('0.5'),
    })

    // 调用sender的transferToFallback，触发fallback合约中fallback函数中的Log事件
    await expect(sender.transferToFallback(fallback.address, {
      value: utils.parseEther('0.5'),
    })).to.emit(fallback, 'Log')

    console.log(await fallback.filters.Log())

    console.log(utils.formatEther(await provider.getBalance(sender.address)))
    console.log(utils.formatEther(await provider.getBalance(fallback.address)))
    console.log(utils.formatEther(await owner.getBalance()))
  })
})
