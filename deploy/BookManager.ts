import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { base } from 'viem/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()
  const Book = await deploy('Book', {
    from: deployer,
    args: [],
    log: true,
  })
  const chainId = await hre.getChainId()

  const baseURI = `https://clober.io/api/nft/chains/${chainId}/orders/`
  const contractURI = `https://clober.io/api/contract/chains/${chainId}`
  let args: any[] = []
  if (deployer == '0x5F79EE8f8fA862E98201120d83c4eC39D9468D49') {
    // Testnet
    args = [deployer, deployer, 'baseURI', 'contractURI', 'Clober Orderbook Maker Order', 'CLOB-ORDER']
  } else if (chainId == base.id.toString()) {
    args = [
      '0xfb976Bae0b3Ef71843F1c6c63da7Df2e44B3836d', // Safe
      '0xfc5899d93df81ca11583bee03865b7b13ce093a7', // Treasury
      baseURI,
      contractURI,
      'Clober Orderbook Maker Order',
      'CLOB-ORDER',
    ]
  } else {
    throw new Error('Unknown chain')
  }

  await deploy('BookManager', {
    from: deployer,
    args: args,
    log: true,
    libraries: {
      Book: Book.address,
    },
  })
}

deployFunction.tags = ['BookManager']
deployFunction.dependencies = []
export default deployFunction
