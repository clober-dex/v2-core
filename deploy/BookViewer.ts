import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { getDeployedAddress } from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  await deploy('BookViewer', {
    from: deployer,
    args: [await getDeployedAddress('BookManager')],
    log: true,
    proxy: true,
  })
}

deployFunction.tags = ['BookViewer']
deployFunction.dependencies = ['BookManager']
export default deployFunction
