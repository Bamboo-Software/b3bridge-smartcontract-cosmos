require('@nomicfoundation/hardhat-toolbox');
require('dotenv').config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || '0x0000000000000000000000000000000000000000000000000000000000000000';

module.exports = {
  solidity: {
    version: '0.8.20',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    seitestnet: {
      url: 'https://evm-rpc-testnet.sei-apis.com',
      accounts: [PRIVATE_KEY],
      chainId: 1328,
      gasPrice: 'auto'
    },
    seimainnet: {
      url: 'https://evm-rpc.sei-apis.com',
      accounts: [PRIVATE_KEY],
      chainId: 1329,
      gasPrice: 2000000000
    },
    hardhat: {
      chainId: 31337
    }
  },
  etherscan: {
    apiKey: {
      seitestnet: 'YOUR_SEITRACE_API_KEY',
      seimainnet: 'YOUR_SEITRACE_API_KEY',
    },
    customChains: [
      {
        network: 'seitestnet',
        chainId: 1328,
        urls: {
          apiURL: 'https://seitrace.com/arctic-1/api',
          browserURL: 'https://seitrace.com',
        },
      },
      {
        network: 'seimainnet',
        chainId: 1329,
        urls: {
          apiURL: 'https://seitrace.com/arctic-1/api',
          browserURL: 'https://seitrace.com',
        },
      },
    ],
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts'
  },
  mocha: {
    timeout: 40000
  }
};
