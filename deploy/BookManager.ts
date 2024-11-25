import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { deployWithVerify } from '../utils'
import { Address } from 'viem'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const deployer = (await getNamedAccounts())['deployer'] as Address

  if (await deployments.getOrNull('BookManager')) {
    return
  }

  let bookLibraryAddress = (await deployments.getOrNull('Book'))?.address
  if (!bookLibraryAddress) {
    bookLibraryAddress = await deployWithVerify(hre, 'Book', [])
  }

  let owner: Address = deployer
  let defaultProvider = '0xfc5899d93df81ca11583bee03865b7b13ce093a7' // Treasury

  await deployWithVerify(
    hre,
    'BookManager',
    [
      owner,
      defaultProvider,
      `https://clober.io/api/nft/chains/124832/orders/`,
      `https://clober.io/api/contract/chains/124832`,
      'Clober Orderbook Maker Order',
      'CLOB-ORDER',
      '0x06f2f407D6977C93550db3798cdF07B87c4eF63e',
      owner,
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
