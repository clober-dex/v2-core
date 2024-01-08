import { HardhatRuntimeEnvironment } from 'hardhat/types'

let HRE: HardhatRuntimeEnvironment | undefined
export const getHRE = (): HardhatRuntimeEnvironment => {
  if (!HRE) {
    HRE = require('hardhat')
  }
  return HRE as HardhatRuntimeEnvironment
}

export const liveLog = (...data: any[]): void => {
  if (getHRE().network.name !== 'localhost') {
    console.log(...data)
  }
}

export const convertToDateString = (utc: number): string => {
  return new Date(utc * 1000).toLocaleDateString('ko-KR', {
    year: '2-digit',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

export const sleep = (ms: number): Promise<void> => {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
