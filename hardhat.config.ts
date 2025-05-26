import path from 'path'
import fs from 'fs'

import * as dotenv from 'dotenv'
import readlineSync from 'readline-sync'

import 'hardhat-deploy'
import '@matterlabs/hardhat-zksync-deploy'
import '@matterlabs/hardhat-zksync-solc'
import '@matterlabs/hardhat-zksync-verify'
import '@nomicfoundation/hardhat-viem'
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-verify'
import 'hardhat-gas-reporter'
import 'hardhat-contract-sizer'
import 'hardhat-abi-exporter'

import { HardhatConfig } from 'hardhat/types'
import * as networkInfos from 'viem/chains'

dotenv.config()

const chainIdMap: { [key: string]: string } = {}
for (const [networkName, networkInfo] of Object.entries(networkInfos)) {
  // @ts-ignore
  chainIdMap[networkInfo.id] = networkName
}

const SKIP_LOAD = process.env.SKIP_LOAD === 'true'

// Prevent to load scripts before compilation
if (!SKIP_LOAD) {
  const tasksPath = path.join(__dirname, 'task')
  fs.readdirSync(tasksPath)
    .filter((pth) => pth.includes('.ts'))
    .forEach((task) => {
      require(`${tasksPath}/${task}`)
    })
}

let privateKey: string
let ok: string

const loadPrivateKeyFromKeyfile = () => {
  let network
  for (const [i, arg] of Object.entries(process.argv)) {
    if (arg === '--network') {
      network = parseInt(process.argv[parseInt(i) + 1])
      if (network.toString() in chainIdMap && ok !== 'Y') {
        ok = readlineSync.question(`You are trying to use ${chainIdMap[network.toString()]} network [Y/n] : `)
        if (ok !== 'Y') {
          throw new Error('Network not allowed')
        }
      }
    }
  }

  const prodNetworks = new Set<number>([
    networkInfos.mainnet.id,
    networkInfos.arbitrum.id,
    networkInfos.base.id,
    networkInfos.zkSync.id,
  ])
  if (network && prodNetworks.has(network)) {
    if (privateKey) {
      return privateKey
    }
    const keythereum = require('keythereum')

    const KEYSTORE = './deployer-key.json'
    const PASSWORD = readlineSync.question('Password: ', {
      hideEchoBack: true,
    })
    if (PASSWORD !== '') {
      const keyObject = JSON.parse(fs.readFileSync(KEYSTORE).toString())
      privateKey = '0x' + keythereum.recover(PASSWORD, keyObject).toString('hex')
    } else {
      privateKey = '0x0000000000000000000000000000000000000000000000000000000000000001'
    }
    return privateKey
  }
  return '0x0000000000000000000000000000000000000000000000000000000000000001'
}

const config: HardhatConfig = {
  zksolc: {
    version: 'latest', // Uses latest available in https://github.com/matter-labs/zksolc-bin/
    settings: {
      libraries: {
        'src/libraries/Book.sol': {
          Book: '0xAc742Cf41d12fA3835f2c658897D5D64a02eCEF8',
        },
      },
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.25',
        settings: {
          evmVersion: 'cancun',
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    ],
    overrides: {},
  },
  defaultNetwork: 'hardhat',
  networks: {
    [networkInfos.sepolia.id]: {
      url: networkInfos.sepolia.rpcUrls.default.http[0],
      chainId: networkInfos.sepolia.id,
      accounts: process.env.DEV_PRIVATE_KEY ? [process.env.DEV_PRIVATE_KEY] : [],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['testnet', 'test'],
      companionNetworks: {},
    },
    [networkInfos.zkSyncSepoliaTestnet.id]: {
      url: networkInfos.zkSyncSepoliaTestnet.rpcUrls.default.http[0],
      chainId: networkInfos.zkSyncSepoliaTestnet.id,
      accounts: process.env.DEV_PRIVATE_KEY ? [process.env.DEV_PRIVATE_KEY] : [],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['testnet', 'test'],
      companionNetworks: {},
      ethNetwork: 'sepolia', // The Ethereum Web3 RPC URL, or the identifier of the network (e.g. `mainnet` or `sepolia`)
      verifyURL: 'https://explorer.sepolia.era.zksync.dev/contract_verification',
      zksync: true,
    },
    [networkInfos.zkSync.id]: {
      url: networkInfos.zkSync.rpcUrls.default.http[0],
      chainId: networkInfos.zkSync.id,
      accounts: [loadPrivateKeyFromKeyfile()],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['mainnet', 'prod'],
      companionNetworks: {},
      ethNetwork: 'mainnet', // The Ethereum Web3 RPC URL, or the identifier of the network (e.g. `mainnet` or `sepolia`)
      verifyURL: 'https://zksync2-mainnet-explorer.zksync.io/contract_verification',
      zksync: true,
    },
    [networkInfos.berachainTestnetbArtio.id]: {
      url: networkInfos.berachainTestnetbArtio.rpcUrls.default.http[0],
      chainId: networkInfos.berachainTestnetbArtio.id,
      accounts: process.env.DEV_PRIVATE_KEY ? [process.env.DEV_PRIVATE_KEY] : [],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['testnet', 'test'],
      companionNetworks: {},
    },
    [networkInfos.monadTestnet.id]: {
      url: 'https://testnet-rpc.monad.xyz',
      chainId: networkInfos.monadTestnet.id,
      accounts: process.env.DEV_PRIVATE_KEY ? [process.env.DEV_PRIVATE_KEY] : [],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['testnet', 'test'],
      companionNetworks: {},
    },
    [networkInfos.arbitrumSepolia.id]: {
      url: networkInfos.arbitrumSepolia.rpcUrls.default.http[0],
      chainId: networkInfos.arbitrumSepolia.id,
      accounts: process.env.DEV_PRIVATE_KEY ? [process.env.DEV_PRIVATE_KEY] : [],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['testnet', 'test'],
      companionNetworks: {},
    },
    [networkInfos.arbitrum.id]: {
      url: networkInfos.arbitrum.rpcUrls.default.http[0],
      chainId: networkInfos.arbitrum.id,
      accounts: [loadPrivateKeyFromKeyfile()],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['mainnet', 'prod'],
      companionNetworks: {},
    },
    [networkInfos.base.id]: {
      url: networkInfos.base.rpcUrls.default.http[0],
      chainId: networkInfos.base.id,
      accounts: [loadPrivateKeyFromKeyfile()],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['mainnet', 'prod'],
      companionNetworks: {},
    },
    hardhat: {
      chainId: networkInfos.hardhat.id,
      gas: 20000000,
      gasPrice: 250000000000,
      gasMultiplier: 1,
      // @ts-ignore
      // forking: {
      //   enabled: true,
      //   url: 'ARCHIVE_NODE_URL',
      // },
      mining: {
        auto: true,
        interval: 0,
        mempool: {
          order: 'fifo',
        },
      },
      accounts: {
        mnemonic: 'loop curious foster tank depart vintage regret net frozen version expire vacant there zebra world',
        initialIndex: 0,
        count: 10,
        path: "m/44'/60'/0'/0",
        accountsBalance: '10000000000000000000000000000',
        passphrase: '',
      },
      blockGasLimit: 200000000,
      // @ts-ignore
      minGasPrice: undefined,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      allowUnlimitedContractSize: true,
      initialDate: new Date().toISOString(),
      loggingEnabled: false,
      // @ts-ignore
      chains: undefined,
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  abiExporter: [
    // @ts-ignore
    {
      path: './abi',
      runOnCompile: false,
      clear: true,
      flat: true,
      only: [],
      except: [],
      spacing: 2,
      pretty: false,
      filter: () => true,
    },
  ],
  mocha: {
    timeout: 40000000,
    require: ['hardhat/register'],
  },
  // @ts-ignore
  contractSizer: {
    runOnCompile: true,
  },
  etherscan: {
    apiKey: {
      base: process.env.BASESCAN_API_KEY ?? '',
      sepolia: process.env.ETHERSCAN_API_KEY ?? '',
      arbitrumSepolia: process.env.ARBISCAN_API_KEY ?? '',
      [networkInfos.berachainTestnetbArtio.id]: 'verifyContract',
      [networkInfos.monadTestnet.id]: 'DUMMY_VALUE',
    },
    customChains: [
      {
        network: networkInfos.berachainTestnetbArtio.id.toString(),
        chainId: networkInfos.berachainTestnetbArtio.id,
        urls: {
          apiURL: 'https://api.routescan.io/v2/network/testnet/evm/80084/etherscan',
          browserURL: 'https://bartio.beratrail.io',
        },
      },
      {
        network: networkInfos.monadTestnet.id.toString(),
        chainId: networkInfos.monadTestnet.id,
        urls: {
          apiURL: 'https://explorer.monad-testnet.category.xyz/api',
          browserURL: 'https://explorer.monad-testnet.category.xyz',
        },
      },
    ],
    enabled: true,
  },
  sourcify: {
    // Enable Sourcify verification by default
    enabled: true,
    apiUrl: 'https://sourcify.dev/server',
    browserUrl: 'https://repo.sourcify.dev',
  },
}

export default config
