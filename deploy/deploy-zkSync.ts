import { Wallet } from 'zksync-ethers'
import * as ethers from 'ethers'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Deployer } from '@matterlabs/hardhat-zksync-deploy'

// load env file
import dotenv from 'dotenv'
import { getChain } from '@nomicfoundation/hardhat-viem/internal/chains'
import { zkSync, zkSyncSepoliaTestnet } from 'viem/chains'
dotenv.config()

// An example of a deploy script that will deploy and call a simple contract.
export default async function (hre: HardhatRuntimeEnvironment) {
  console.log(`Running deploy script for the BookManager contract`)
  const chain = await getChain(hre.network.provider)
  if (chain.id !== zkSyncSepoliaTestnet.id && chain.id !== zkSync.id) {
    throw new Error('Unsupported chain')
  }

  // Initialize the wallet.
  const accounts = hre.config.networks[chain.id].accounts
  if (!Array.isArray(accounts)) throw new Error('Invalid accounts')
  const privateKey = accounts[0]
  if (!privateKey) throw new Error('Private key not found')
  if (typeof privateKey !== 'string') throw new Error('Invalid private key')
  const wallet = new Wallet(privateKey)

  // Create deployer object and load the artifact of the contract you want to deploy.
  const deployer = new Deployer(hre, wallet)
  const artifact = await deployer.loadArtifact('BookManager')

  // Estimate contract deployment fee
  let owner = ''
  let treasury = ''
  if (chain.id === zkSyncSepoliaTestnet.id) {
    owner = deployer.zkWallet.address
    treasury = deployer.zkWallet.address
  } else if (chain.id === zkSync.id) {
    owner = '0xc0f2c32E7FF56318291c6bfA4C998A2F7213D2e0'
    treasury = '0xfc5899d93df81ca11583bee03865b7b13ce093a7'
  }
  const constructorArguments = [
    owner,
    treasury,
    `https://clober.io/api/nft/chains/${chain.id}/orders/`,
    `https://clober.io/api/contract/chains/${chain.id}`,
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
