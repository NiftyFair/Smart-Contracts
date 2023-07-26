require("dotenv").config();
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-ethers");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("@nomiclabs/hardhat-solhint");
require("hardhat-contract-sizer");
require("@openzeppelin/hardhat-upgrades");
require("@openzeppelin/test-helpers");
require("@nomiclabs/hardhat-web3");

require("@matterlabs/hardhat-zksync-solc");
require("@matterlabs/hardhat-zksync-deploy");

const PRIVATE_KEY = process.env.PRIVATE_KEY;

module.exports = {
  zksolc: {
    version: "latest", // Uses latest available in https://github.com/matter-labs/zksolc-bin/
    settings: {},
  },
  solidity: {
    compilers: [
      {
        version: "0.4.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  gasReporter: {
    currency: "USD",
    enabled: false,
    gasPrice: 50,
  },
  networks: {
    gc: {
      url: "https://rpc.gnosischain.com",
      zksync: false,
      chainId: 100,
      accounts: [`0x${PRIVATE_KEY}`],
    },

    zksync: {
      url: "https://mainnet.era.zksync.io",
      zksync: true,
      ethNetwork: "mainnet",
      chainId: 324,
      accounts: [`0x${PRIVATE_KEY}`],
    },

    zksynctest: {
      url: "https://testnet.era.zksync.dev",
      zksync: true,
      ethNetwork: "goerli",
      chainId: 280,
      accounts: [`0x${PRIVATE_KEY}`],
    },

    coverage: {
      url: "http://localhost:8555",
    },

    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
};
