import { Address, decodeEventLog, encodeDeployData, getContract, Hex, keccak256, parseAbi, toHex } from 'viem'
import { getHRE, liveLog, sleep } from './misc'
import { artifacts } from 'hardhat'
import { Libraries } from 'hardhat-deploy/dist/types'

export const CreateXFactoryAddress = '0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed'

export const CreateXFactoryAbi = parseAbi([
  'error FailedContractCreation(address)',
  'error FailedContractInitialisation(address,bytes)',
  'error FailedEtherTransfer(address,bytes)',
  'error InvalidNonceValue(address)',
  'error InvalidSalt(address)',
  'event ContractCreation(address indexed,bytes32 indexed)',
  'event ContractCreation(address indexed)',
  'event Create3ProxyContractCreation(address indexed,bytes32 indexed)',
  'function computeCreate2Address(bytes32,bytes32) view returns (address)',
  'function computeCreate2Address(bytes32,bytes32,address) pure returns (address)',
  'function computeCreate3Address(bytes32,address) pure returns (address)',
  'function computeCreate3Address(bytes32) view returns (address)',
  'function computeCreateAddress(uint256) view returns (address)',
  'function computeCreateAddress(address,uint256) view returns (address)',
  'function deployCreate(bytes) payable returns (address)',
  'function deployCreate2(bytes32,bytes) payable returns (address)',
  'function deployCreate2(bytes) payable returns (address)',
  'function deployCreate2AndInit(bytes32,bytes,bytes,(uint256,uint256),address) payable returns (address)',
  'function deployCreate2AndInit(bytes,bytes,(uint256,uint256)) payable returns (address)',
  'function deployCreate2AndInit(bytes,bytes,(uint256,uint256),address) payable returns (address)',
  'function deployCreate2AndInit(bytes32,bytes,bytes,(uint256,uint256)) payable returns (address)',
  'function deployCreate2Clone(bytes32,address,bytes) payable returns (address)',
  'function deployCreate2Clone(address,bytes) payable returns (address)',
  'function deployCreate3(bytes) payable returns (address)',
  'function deployCreate3(bytes32,bytes) payable returns (address)',
  'function deployCreate3AndInit(bytes32,bytes,bytes,(uint256,uint256)) payable returns (address)',
  'function deployCreate3AndInit(bytes,bytes,(uint256,uint256)) payable returns (address)',
  'function deployCreate3AndInit(bytes32,bytes,bytes,(uint256,uint256),address) payable returns (address)',
  'function deployCreate3AndInit(bytes,bytes,(uint256,uint256),address) payable returns (address)',
  'function deployCreateAndInit(bytes,bytes,(uint256,uint256)) payable returns (address)',
  'function deployCreateAndInit(bytes,bytes,(uint256,uint256),address) payable returns (address)',
  'function deployCreateClone(address,bytes) payable returns (address)',
])

export const deployCreate3WithVerify = async (
  deployer: Address,
  entropy: bigint,
  contractNameOrFullyQualifiedName: string,
  args: any[],
  options?: {
    libraries?: Libraries
  },
): Promise<Address> => {
  if (entropy >= 2n ** 88n) {
    throw new Error('Entropy too large')
  }
  const hre = getHRE()

  const artifact = await artifacts.readArtifact(contractNameOrFullyQualifiedName)

  let bytecode = artifact.bytecode as Hex
  if (options?.libraries) {
    for (const [libraryName, libraryAddress] of Object.entries(options.libraries)) {
      const libArtifact = await artifacts.readArtifact(libraryName)
      const key =
        '__\\$' + keccak256(toHex(libArtifact.sourceName + ':' + libArtifact.contractName)).slice(2, 36) + '\\$__'
      bytecode = bytecode.replace(new RegExp(key, 'g'), libraryAddress.slice(2)) as Hex
    }
  }

  const initcode = encodeDeployData({ abi: artifact.abi, bytecode, args })

  const salt = (deployer + '00' + entropy.toString(16).padStart(22, '0')) as Hex

  const createXFactory = getContract({
    abi: CreateXFactoryAbi,
    address: CreateXFactoryAddress,
    client: await hre.viem.getWalletClient(deployer),
  })
  const publicClient = await hre.viem.getPublicClient()

  const computedAddress = await createXFactory.read.computeCreate3Address([salt])
  liveLog('Computed address', computedAddress)

  const remoteBytecode = await publicClient.getBytecode({ address: computedAddress })
  if (remoteBytecode && remoteBytecode.length > 0) {
    liveLog('Contract already deployed at', computedAddress)
    return computedAddress
  }

  const txHash = await createXFactory.write.deployCreate3([salt, initcode])
  const receipt = await publicClient.getTransactionReceipt({ hash: txHash }).catch((e) => {
    if (e.shortMessage && e.shortMessage.includes('The Transaction may not be processed on a block yet.')) {
      return sleep(500).then(() => publicClient.getTransactionReceipt({ hash: txHash }))
    }
    throw e
  })
  const event = receipt.logs
    .filter((log) => log.address.toLowerCase() === CreateXFactoryAddress.toLowerCase())
    .map((log) => decodeEventLog({ abi: createXFactory.abi, data: log.data, topics: log.topics }))
    .find((log) => log.eventName === 'ContractCreation')
  if (!event) {
    throw new Error('Contract creation event not found')
  }
  const deployedAddress = event.args[0]

  liveLog('Contract created at', deployedAddress)

  try {
    await hre.run('verify:verify', {
      address: deployedAddress,
      constructorArguments: args,
    })
  } catch (e) {
    console.log(e)
  }

  await hre.deployments.save(contractNameOrFullyQualifiedName, {
    address: deployedAddress,
    abi: artifact.abi,
    transactionHash: txHash,
    args,
    bytecode,
  })

  return deployedAddress
}
