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

const PRIVATE_KEY = process.env.PRIVATE_KEY;

module.exports = {
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
      url: `https://rpc.gnosischain.com`,
      chainId: 100,
      accounts: [`0x${PRIVATE_KEY}`],
    },

    linea: {
      url: `https://rpc.linea.build`,
      chainId: 59144,
      accounts: [`0x${PRIVATE_KEY}`],
    },

    lineaTestnet: {
      url: `https://linea-goerli.infura.io/v3/9a5bdcb7c4ef40b0a5558dfd58836186`,
      chainId: 59140,
      accounts: [`0x${PRIVATE_KEY}`],
    },

    coverage: {
      url: "http://localhost:8555",
    },

    localhost: {
      url: `http://127.0.0.1:8545`,
    },
  },
};
