import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { getChain, isDevelopmentNetwork } from '@nomicfoundation/hardhat-viem/internal/chains'
import { deployWithVerify } from '../utils'
import { base } from 'viem/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deployer } = await getNamedAccounts()
  const chain = await getChain(network.provider)

  if (await deployments.getOrNull('BookManager')) {
    return
  }

  let args: any[] = []
  if (chain.testnet || isDevelopmentNetwork(chain.id)) {
    args = [deployer, deployer, 'baseURI', 'contractURI', 'Clober Orderbook Maker Order', 'CLOB-ORDER']
  } else if (chain.id === base.id) {
    args = [
      '0xfb976Bae0b3Ef71843F1c6c63da7Df2e44B3836d', // Safe
      '0xfc5899d93df81ca11583bee03865b7b13ce093a7', // Treasury
      `https://clober.io/api/nft/chains/${chain.id}/orders/`,
      `https://clober.io/api/contract/chains/${chain.id}`,
      'Clober Orderbook Maker Order',
      'CLOB-ORDER',
    ]
  } else {
    throw new Error('Unknown chain')
  }

  await deployWithVerify(hre, 'BookManager', args)
}

deployFunction.tags = ['BookManager']
deployFunction.dependencies = []
export default deployFunction
