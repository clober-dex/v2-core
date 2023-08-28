import { BigNumber, utils } from 'ethers'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'

let HRE: HardhatRuntimeEnvironment | undefined
export const getHRE = (): HardhatRuntimeEnvironment => {
  if (!HRE) {
    HRE = require('hardhat')
  }
  return HRE as HardhatRuntimeEnvironment
}

export const liveLog = (str: string): void => {
  if (getHRE().network.name !== hardhat.name) {
    console.log(str)
  }
}

export const bn2StrWithPrecision = (bn: BigNumber, precision: number): string => {
  const prec = BigNumber.from(10).pow(precision)
  const q = bn.div(prec)
  const r = bn.mod(prec)
  return q.toString() + '.' + r.toString().padStart(precision, '0')
}

export const convertToDateString = (utc: BigNumber): string => {
  return new Date(utc.toNumber() * 1000).toLocaleDateString('ko-KR', {
    year: '2-digit',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

export const verify = async (contractAddress: string, args: any[]) => {
  liveLog(`Verifying Contract: ${contractAddress}`)
  try {
    await getHRE().run('verify:verify', {
      address: contractAddress,
      constructorArguments: args,
    })
  } catch (e) {
    console.log(e)
  }
}

export const sleep = (ms: number): Promise<void> => {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export const computeCreate1Address = (origin: string, nonce: BigNumber): string => {
  let packedData: string
  if (nonce.eq(BigNumber.from('0x00'))) {
    packedData = utils.solidityPack(['bytes1', 'bytes1', 'address', 'bytes1'], ['0xd6', '0x94', origin, '0x80'])
  } else if (nonce.lte(BigNumber.from('0x7f'))) {
    packedData = utils.solidityPack(
      ['bytes1', 'bytes1', 'address', 'bytes1'],
      ['0xd6', '0x94', origin, nonce.toHexString()],
    )
  } else if (nonce.lte(BigNumber.from('0xff'))) {
    packedData = utils.solidityPack(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint8'],
      ['0xd7', '0x94', origin, '0x81', nonce.toHexString()],
    )
  } else if (nonce.lte(BigNumber.from('0xffff'))) {
    packedData = utils.solidityPack(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint16'],
      ['0xd8', '0x94', origin, '0x82', nonce.toHexString()],
    )
  } else if (nonce.lte(BigNumber.from('0xffffff'))) {
    packedData = utils.solidityPack(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint24'],
      ['0xd9', '0x94', origin, '0x83', nonce.toHexString()],
    )
  } else if (nonce.lte(BigNumber.from('0xffffffff'))) {
    packedData = utils.solidityPack(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint32'],
      ['0xda', '0x94', origin, '0x84', nonce.toHexString()],
    )
  } else if (nonce.lte(BigNumber.from('0xffffffffff'))) {
    packedData = utils.solidityPack(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint40'],
      ['0xdb', '0x94', origin, '0x85', nonce.toHexString()],
    )
  } else if (nonce.lte(BigNumber.from('0xffffffffffff'))) {
    packedData = utils.solidityPack(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint48'],
      ['0xdc', '0x94', origin, '0x86', nonce.toHexString()],
    )
  } else if (nonce.lte(BigNumber.from('0xffffffffffffff'))) {
    packedData = utils.solidityPack(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint56'],
      ['0xdd', '0x94', origin, '0x87', nonce.toHexString()],
    )
  } else if (nonce.lt(BigNumber.from('0xffffffffffffffff'))) {
    packedData = utils.solidityPack(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint64'],
      ['0xde', '0x94', origin, '0x88', nonce.toHexString()],
    )
  } else {
    // Cannot deploy contract when the nonce is type(uint64).max
    throw new Error('MAX_NONCE')
  }
  return '0x' + utils.keccak256(packedData).slice(-40)
}
