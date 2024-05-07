import { Wallet } from 'zksync-ethers'
import * as ethers from 'ethers'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Deployer } from '@matterlabs/hardhat-zksync-deploy'

// load env file
import dotenv from 'dotenv'
dotenv.config()

// load wallet private key from env file
const PRIVATE_KEY = process.env.DEV_PRIVATE_KEY || ''

if (!PRIVATE_KEY) throw '⛔️ Private key not detected! Add it to the .env file!'

// An example of a deploy script that will deploy and call a simple contract.
export default async function (hre: HardhatRuntimeEnvironment) {
  console.log(`Running deploy script for the BookManager contract`)

  // Initialize the wallet.
  const wallet = new Wallet(PRIVATE_KEY)

  // Create deployer object and load the artifact of the contract you want to deploy.
  const deployer = new Deployer(hre, wallet)
  const artifact = await deployer.loadArtifact('BookManager')

  // Estimate contract deployment fee
  const constructorArguments = [
    deployer.zkWallet.address,
    deployer.zkWallet.address,
    'baseURI',
    'contractURI',
    'Clober Orderbook Maker Order',
    'CLOB-ORDER',
  ]
  const deploymentFee = await deployer.estimateDeployFee(artifact, constructorArguments)
  const parsedFee = ethers.formatEther(deploymentFee)
  console.log(`The deployment is estimated to cost ${parsedFee} ETH`)

  const contract = await deployer.deploy(artifact, constructorArguments)

  //obtain the Constructor Arguments
  console.log('constructor args:' + contract.interface.encodeDeploy(constructorArguments))

  // Show the contract info.
  const contractAddress = await contract.getAddress()
  console.log(`${artifact.contractName} was deployed to ${contractAddress}`)

  await hre.run('verify:verify', {
    address: contractAddress,
    constructorArguments,
    contract: 'src/BookManager.sol:BookManager',
  })
}
