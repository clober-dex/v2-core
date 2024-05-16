import {
  Address,
  decodeEventLog,
  encodeAbiParameters,
  encodeDeployData,
  getContract,
  Hex,
  keccak256,
  parseAbi,
  toHex,
} from 'viem'
import { getHRE, liveLog, sleep } from './misc'
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
  name: string,
  args: any[],
  options?: {
    libraries?: Libraries
    contract?: string
  },
): Promise<Address> => {
  if (entropy >= 2n ** 88n) {
    throw new Error('Entropy too large')
  }
  liveLog('Create3 deploying', name, 'with entropy', entropy.toString(16))
  if (!options) {
    options = {}
  }
  const hre = getHRE()

  const artifact = await hre.artifacts.readArtifact(options.contract ? options.contract : name)

  let bytecode = artifact.bytecode as Hex
  if (options?.libraries) {
    for (const [libraryName, libraryAddress] of Object.entries(options.libraries)) {
      const libArtifact = await hre.artifacts.readArtifact(libraryName)
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

  const guardedSalt = keccak256(encodeAbiParameters([{ type: 'address' }, { type: 'bytes32' }], [deployer, salt]))
  let address: Address = await createXFactory.read.computeCreate3Address([guardedSalt])
  liveLog('Computed address', address)

  const remoteBytecode = await publicClient.getBytecode({ address })
  let txHash: Hex = '0x'
  if (remoteBytecode && remoteBytecode.length > 0) {
    liveLog('Contract already deployed at', address, '\n')
  } else {
    txHash = await createXFactory.write.deployCreate3([salt, initcode])
    const receipt = await publicClient.getTransactionReceipt({ hash: txHash }).catch(async () => {
      await sleep(500)
      return publicClient.getTransactionReceipt({ hash: txHash })
    })
    const event = receipt.logs
      .filter((log) => log.address.toLowerCase() === CreateXFactoryAddress.toLowerCase())
      .map((log) => decodeEventLog({ abi: createXFactory.abi, data: log.data, topics: log.topics }))
      .find((log) => log.eventName === 'ContractCreation')
    if (!event) {
      throw new Error('Contract creation event not found')
    }
    address = event.args[0]

    liveLog('Contract created at', address, '\n')
  }

  try {
    await hre.run('verify:verify', {
      address: address,
      constructorArguments: args,
    })
  } catch (e) {
    console.log(e)
  }

  await hre.deployments.save(name, {
    address: address,
    abi: artifact.abi,
    transactionHash: txHash,
    args,
    bytecode,
  })

  return address
}
