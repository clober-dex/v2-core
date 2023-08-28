import { Contract, ContractTransaction } from 'ethers'

import { getHRE } from './misc'

export const waitForTx = async (tx: Promise<ContractTransaction>, confirmation?: number) => {
  return (await tx).wait(confirmation)
}

export const getDeployedContract = async <T extends Contract>(contractName: string): Promise<T> => {
  const hre = getHRE()
  const deployments = await hre.deployments.get(contractName)
  const contract = await hre.ethers.getContractAt(deployments.abi, deployments.address)
  return contract as T
}
