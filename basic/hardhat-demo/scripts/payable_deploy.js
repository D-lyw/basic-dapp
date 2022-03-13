const { ethers } = require('hardhat')

async function main() {
  const Payable = await ethers.getContractFactory('Payable')
  const payable = await Payable.deploy()

  await payable.deployed()

  console.log('Payable deployed to: ', payable.address)
}

main()
  .then(() => {
    process.exit(0)
  })
  .catch(err => console.error(err))
