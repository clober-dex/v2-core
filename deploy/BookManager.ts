import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()
  const Book = await deploy('Book', {
    from: deployer,
    args: [],
    log: true,
  })

  let args: any[] = []
  if (deployer == '0x5F79EE8f8fA862E98201120d83c4eC39D9468D49') {
    // Testnet
    args = [deployer, deployer, 'baseURI', 'contractURI', 'Clober Orderbook Maker Order', 'CLOB-ORDER']
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
