import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { getChain, isDevelopmentNetwork } from '@nomicfoundation/hardhat-viem/internal/chains'
import { deployCreate3WithVerify, deployWithVerify } from '../utils'
import { base } from 'viem/chains'
import { Address } from 'viem'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const deployer = (await getNamedAccounts())['deployer'] as Address
  const chain = await getChain(network.provider)

  if (await deployments.getOrNull('BookManager')) {
    return
  }

  let bookLibraryAddress = (await deployments.getOrNull('Book'))?.address
  if (!bookLibraryAddress) {
    bookLibraryAddress = await deployWithVerify(hre, 'Book', [])
  }

  let owner: Address = '0x'
  let defaultProvider: Address = '0x'
  if (chain.testnet || isDevelopmentNetwork(chain.id)) {
    owner = defaultProvider = deployer
  } else if (chain.id === base.id) {
    owner = '0xfb976Bae0b3Ef71843F1c6c63da7Df2e44B3836d' // Safe
    defaultProvider = '0xfc5899d93df81ca11583bee03865b7b13ce093a7' // Treasury
  } else {
    throw new Error('Unknown chain')
  }

  const entropy = 1000n
  await deployCreate3WithVerify(
    deployer,
    entropy,
    'BookManager',
    [
      owner,
      defaultProvider,
      `https://clober.io/api/nft/chains/${chain.id}/orders/`,
      `https://clober.io/api/contract/chains/${chain.id}`,
      'Clober Orderbook Maker Order',
      'CLOB-ORDER',
    ],
    {
      libraries: {
        Book: bookLibraryAddress,
      },
    },
  )
}

deployFunction.tags = ['BookManager']
deployFunction.dependencies = []
export default deployFunction
