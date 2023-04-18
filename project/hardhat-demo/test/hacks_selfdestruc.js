const { expect } = require('chai')
const { utils } = require('ethers')
const { ethers } = require('hardhat')

require('@nomiclabs/hardhat-waffle')

describe('EtherGame', () => {
  let etherGame, attack
  let owner, addr1
  before(async () => {
    ;[owner, addr1] = await ethers.getSigners()
    const EtherGame = await ethers.getContractFactory('EtherGame')
    etherGame = await EtherGame.deploy()
    await etherGame.deployed()

    const Attack = await ethers.getContractFactory('Attack2')
    attack = await Attack.deploy(etherGame.address)
    await attack.deployed()
  })

  it('send Ether', async () => {
    await expect(
      etherGame.deposit({ value: utils.parseEther('2') })
    ).to.be.revertedWith('only can send 1 ether')

    await etherGame.deposit({ value: utils.parseEther('1') })
    await etherGame.connect(addr1).deposit({ value: utils.parseEther('1') })

    expect(await ethers.provider.getBalance(etherGame.address)).to.be.equal(
      utils.parseEther('2')
    )
  })

  it('attack', async () => {
    await attack.attack({ value: utils.parseEther('6') })
    expect(await ethers.provider.getBalance(etherGame.address)).to.be.equal(
      utils.parseEther('8')
    )
    await expect(
      etherGame.deposit({ value: utils.parseEther('1') })
    ).to.be.revertedWith('game over')
  })
})
