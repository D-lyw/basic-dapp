require('@nomiclabs/hardhat-waffle')
const { expect } = require('chai')
const { utils } = require('ethers')
const { ethers } = require('hardhat')

describe('EtherStore', () => {
  let etherStore
  let addr1, addr2, addr3
  before(async () => {
    ;[addr1, addr2, addr3] = await ethers.getSigners()
    const EtherStore = await ethers.getContractFactory('EtherStore')
    etherStore = await EtherStore.deploy()
    await etherStore.deployed()
  })

  it('Send Ether', async () => {
    await etherStore.deposit({ value: utils.parseEther('1') })
    await etherStore.connect(addr2).deposit({ value: utils.parseEther('2') })
    await etherStore.connect(addr3).deposit({ value: utils.parseEther('3') })
    expect(await etherStore.getBalance()).to.be.equal(utils.parseEther('6'))
    expect(await etherStore.accounts(addr2.address)).to.be.equal(
      utils.parseEther('2')
    )
  })

  describe('Attack', () => {
    let attack
    let owner
    before(async () => {
      ;[owner] = await ethers.getSigners()
      const Attack = await ethers.getContractFactory('Attack')
      attack = await Attack.deploy(etherStore.address)
      await attack.deployed()
    })

    it('Send ether to Attack Contract', async () => {
      // 先给攻击合约充值Ether
      await attack.deposit({ value: utils.parseEther('1') })

      // 攻击
      await attack.attack()

      // 攻击者余额
      const attackBalance = await attack.getBalance()
      // 被攻击合约余额
      const attackedContractBalance = await etherStore.getBalance()
      console.log(
        utils.formatEther(attackBalance),
        utils.formatEther(attackedContractBalance)
      )
      // get 7 ether (6 got from contract, 1 from itself)
      expect(attackBalance).to.be.equal(utils.parseEther('7'))
      expect(attackedContractBalance).to.be.equal(utils.parseEther('0'))
    })
  })
})
