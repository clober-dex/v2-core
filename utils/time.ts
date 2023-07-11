import { ethers } from 'hardhat'
import { BigNumber } from 'ethers'

export const advanceBlock = async (count: number = 1): Promise<void> => {
  for (let i = 0; i < count; i++) {
    await ethers.provider.send('evm_mine', [])
  }
}

export const advanceBlockTo = async (blockNumber: number): Promise<void> => {
  let i = await ethers.provider.getBlockNumber()
  while (i < blockNumber) {
    await advanceBlock()
    i = await ethers.provider.getBlockNumber()
  }
}

export const advanceTime = async (time: number | BigNumber): Promise<void> => {
  if (typeof time === 'number') {
    await ethers.provider.send('evm_increaseTime', [time])
  } else {
    await ethers.provider.send('evm_increaseTime', [time.toNumber()])
  }
}

export const latestTime = async (): Promise<BigNumber> => {
  const block = await ethers.provider.getBlock('latest')
  return BigNumber.from(block.timestamp)
}

export const latestNumber = async (): Promise<BigNumber> => {
  const block = await ethers.provider.getBlock('latest')
  return BigNumber.from(block.number)
}

export const advanceTimeAndBlock = async (
  time: number | BigNumber,
): Promise<void> => {
  await advanceTime(time)
  await advanceBlock()
}

export const duration = {
  seconds: function (val: any): BigNumber {
    return BigNumber.from(val)
  },
  minutes: function (val: any): BigNumber {
    return BigNumber.from(val).mul(this.seconds('60'))
  },
  hours: function (val: any): BigNumber {
    return BigNumber.from(val).mul(this.minutes('60'))
  },
  days: function (val: any): BigNumber {
    return BigNumber.from(val).mul(this.hours('24'))
  },
  weeks: function (val: any): BigNumber {
    return BigNumber.from(val).mul(this.days('7'))
  },
  years: function (val: any): BigNumber {
    return BigNumber.from(val).mul(this.days('365'))
  },
}
