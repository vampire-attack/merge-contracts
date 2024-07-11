import { HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.19",
  networks: {
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${vars.get("VULTISIG_ALCHEMY_KEY")}`,
      chainId: 11155111,
      accounts: [vars.get("VAMP_DEPLOYER_KEY")],
    },
  },
  etherscan: {
    apiKey: {
      base: vars.get("ETHERSCAN_KEY"),
    },
  },
};

export default config;
