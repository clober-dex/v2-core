import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()
  const DEFAULT_PROVIDER = '' // TODO: add default provider address
  await deploy('BookManager', {
    from: deployer,
    args: [DEFAULT_PROVIDER],
    log: true,
  })
}

deployFunction.tags = ['BookManager']
deployFunction.dependencies = []
export default deployFunction
