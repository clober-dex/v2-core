import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const deployFunction: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment,
) {
  const { ethers, deployments, getNamedAccounts } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()
  await deploy('Greeter', {
    from: deployer,
    args: ['Hello, solidity!'],
    // proxy: {
    //   proxyContract: "OpenZeppelinTransparentProxy",
    //   execute: {
    //     init: {
    //       methodName: "INIT_METHOD_NAME",
    //       args: [],
    //     }
    //   }
    // },
    log: true,
  })
}

deployFunction.tags = ['Greeter']
deployFunction.dependencies = []
export default deployFunction
