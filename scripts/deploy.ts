import fs from "fs";
import hre, { ethers } from "hardhat";

async function main() {
  const network = hre.network.name as "mainnet" | "sepolia";
  const vamp = await ethers.deployContract("Token", ["Vamp Token", "VAMP"]);
  await vamp.waitForDeployment();

  // Deploy test mock tokens
  const target1 = await ethers.deployContract("Token", ["Target Asset 1", "TAR1"]);
  await target1.waitForDeployment();

  const target2 = await ethers.deployContract("Token", ["Target Asset 2", "TAR2"]);
  await target2.waitForDeployment();

  const vampAddress = await vamp.getAddress();
  const mergeManager = await ethers.deployContract("MergeManager", [vampAddress]);
  await mergeManager.waitForDeployment();

  const deployedContracts = {
    vamp: vampAddress,
    mergeManager: await mergeManager.getAddress(),
  };

  fs.writeFileSync(`./deployment-${network}.json`, JSON.stringify(deployedContracts));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
