require('@nomiclabs/hardhat-waffle')
const { ethers } = require('hardhat')
const { utils } = ethers

describe('MultiWallet', () => {
  let wallet
  let owner
  let addr1, addr2, addr3, addr4

  it('setup', async () => {
    ;[owner, addr1, addr2, addr3, addr4] = await ethers.getSigners()
    const MultiWallet = await ethers.getContractFactory('MultiWallet')

    wallet = await MultiWallet.deploy(
      [
        owner.address,
        addr1.address,
        addr2.address,
        addr3.address,
        addr4.address,
      ],
      3
    )
    await wallet.deployed()

    const owners = await wallet.owners()
    console.log(owners)
  })
})
