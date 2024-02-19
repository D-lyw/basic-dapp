import { formatEther, parseEther } from "viem";
import hre from "hardhat";

async function main() {
  const raffle = await hre.viem.deployContract("Raffle", ["0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625", 9160])

  console.log("Rafflle Contract deployed: ", raffle.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
