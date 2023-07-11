import {
  BigNumber,
  BigNumberish,
  ContractReceipt,
  ContractTransaction,
} from 'ethers'
import { assert, expect } from 'chai'

import { waitForTx } from '../utils/misc'

export const expectSmallDiff = (
  a: BigNumber,
  b: BigNumber,
  diff: BigNumberish = 1,
): void => {
  if (a.gt(b)) {
    expect(a.sub(b)).to.be.lte(diff)
  } else {
    expect(b.sub(a)).to.be.lte(diff)
  }
}

export type ExpectEvent = {
  name: string
  args: any[]
}

export const expectEvent = (
  receipt: ContractReceipt,
  expectedEvent: ExpectEvent,
  index = 0,
): void => {
  assert(receipt.events)
  const event = receipt.events.filter((e) => e.event === expectedEvent.name)[
    index
  ]
  const actualArgs = event.args
  assert(actualArgs)
  expect(actualArgs.length).to.be.equal(expectedEvent.args.length)
  expectedEvent.args.forEach((arg, i) => {
    if (arg === null) {
      // skip if arg is null
      return
    }
    expect(actualArgs[i], `${expectedEvent.name}, index${i}`).to.be.equal(arg)
  })
}

export const logEvents = async (
  tx: Promise<ContractTransaction>,
): Promise<ContractTransaction> => {
  const receipt = await waitForTx(tx)
  receipt.events?.forEach((e) => console.log(e))
  return tx
}
