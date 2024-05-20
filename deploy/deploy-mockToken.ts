import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Wallet } from 'zksync-ethers'
import * as ethers from 'ethers'
import { Deployer } from '@matterlabs/hardhat-zksync-deploy'

// load env file
import dotenv from 'dotenv'
dotenv.config()

// load wallet private key from env file
const PRIVATE_KEY = process.env.DEV_PRIVATE_KEY || ''

if (!PRIVATE_KEY) throw '⛔️ Private key not detected! Add it to the .env file!'

// An example of a deploy script that will deploy and call a simple contract.
export default async function (hre: HardhatRuntimeEnvironment) {
  console.log(`Running deploy script for the Foo contract`)

  // Initialize the wallet.
  const wallet = new Wallet(PRIVATE_KEY)

  // Create deployer object and load the artifact of the contract you want to deploy.
  const deployer = new Deployer(hre, wallet)
  const artifact = await deployer.loadArtifact('Foo')

  // Estimate contract deployment fee
  const args: any[] = []
  const deploymentFee = await deployer.estimateDeployFee(artifact, args)

  // ⚠️ OPTIONAL: You can skip this block if your account already has funds in L2
  // const depositHandle = await deployer.zkWallet.deposit({
  //   to: deployer.zkWallet.address,
  //   token: utils.ETH_ADDRESS,
  //   amount: deploymentFee.mul(2),
  // });
  // // Wait until the deposit is processed on zkSync
  // await depositHandle.wait();

  // Deploy this contract. The returned object will be of a `Contract` type, similar to ones in `ethers`.
  // `greeting` is an argument for contract constructor.
  const parsedFee = ethers.formatEther(deploymentFee)
  console.log(`The deployment is estimated to cost ${parsedFee} ETH`)

  const greeterContract = await deployer.deploy(artifact, args)

  //obtain the Constructor Arguments
  console.log('constructor args:' + greeterContract.interface.encodeDeploy(args))

  // Show the contract info.
  const contractAddress = await greeterContract.getAddress()
  console.log(`${artifact.contractName} was deployed to ${contractAddress}`)

  await hre.run('verify:verify', {
    address: contractAddress,
    args,
    contract: 'src/Foo.sol:Foo',
  })
}
