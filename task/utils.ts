import { task } from 'hardhat/config'
import { utils, Provider, Contract, Wallet } from 'zksync-ethers'
import { encodeAbiParameters, encodeFunctionData, Hex, keccak256, zeroAddress } from 'viem'

task('utils:accounts', 'Prints the list of accounts').setAction(async (taskArgs, hre) => {
  console.log(await hre.getNamedAccounts())
  console.log(await hre.getUnnamedAccounts())
})

task('utils:get-block', 'Print latest block')
  .addOptionalParam('where', 'block hash or block tag', 'latest')
  .setAction(async (taskArgs, hre) => {
    const block = await (await hre.viem.getPublicClient()).getBlock()
    console.log(block)
  })

task('ttt').setAction(async (taskArgs, hre) => {
  const bm = await hre.viem.getContractAt('BookManager', '0x50d2BaAe58D13757aFcA5a735CC1D2dDE1ceE0e5')
  const orderId = 81177068471485603709267478311745501823984771275353499276050752082067293470721n
  const bookId = orderId >> 64n
  const tick = (orderId >> 40n) & 0xffffffn
  const orderIndex = orderId & 0xffffffffffn
  console.log(bookId, Number(tick), orderIndex)
  const wallet = await hre.viem.getWalletClient('0x5F79EE8f8fA862E98201120d83c4eC39D9468D49')
  // const res = await wallet.sendTransaction({
  //   to: bm.address,
  //   data: encodeFunctionData({ abi: bm.abi, functionName: 'getOrder', args: [orderId] }),
  //   gas: 300000n,
  //   gasPerPubData: 50000n,
  // })
  // console.log(res)

  // console.log(await bm.read.getOrder([orderId]))
  // console.log(await bm.read.getOrder([orderId - 1n]))
  // console.log(await bm.read.getDepth([bookId, Number(tick)]))
  // 14n => _books
  const key = keccak256(
    encodeAbiParameters(
      [
        { name: 'x', type: 'uint192' },
        { name: 'y', type: 'uint256' },
      ],
      [bookId, 14n],
    ),
  )
  const queuesKey = BigInt(key) + 3n
  const queueKey = keccak256(
    encodeAbiParameters(
      [
        { name: 'tick', type: 'uint256' },
        { name: 'k', type: 'uint256' },
      ],
      [tick, queuesKey],
    ),
  )
  console.log(await bm.read.load([key, 3n]))
  const orderKey = keccak256(encodeAbiParameters([{ name: 'k', type: 'uint256' }], [BigInt(queueKey) + 4n]))
  console.log(await bm.read.load([bigintToBytes32(BigInt(queueKey) + 4n)]))
  console.log(await bm.read.load([orderKey]))
  console.log(await bm.read.load([bigintToBytes32(BigInt(orderKey) + 1n)]))
  console.log(await bm.read.getBookKey([bookId]))
})

task('sss').setAction(async (taskArgs, hre) => {
  const sc = await hre.viem.getContractAt('Foo', '0x403AD5625DaF273CDEFB060A9bf2204CA509E649')
  console.log(await sc.write.addNumber([123n]))
  console.log(await sc.write.addNumber([333n]))
  console.log(await sc.read.getNumber([0n]))
  console.log(await sc.read.getNumber([1n]))
  console.log(await sc.read.getNumber([0n + (1n << 40n)]))
  console.log(await sc.read.getNumber([1n + (1n << 40n)]))

  // const sc = await hre.viem.getContractAt('BookSlotTest', '0x1e7b29aD68651685df94c77DdC85534DB6C142f8')
  // const sc = await hre.viem.getContractAt('SlotTest', '0xd1d0BB85182f567E434624EC05CCe572e0423C5F')
  //
  // const res = await sc.write.addSample(['0xd1d0BB85182f567E434624EC05CCe572e0423C5F', 1234n])
  // console.log(res)
  // console.log(await sc.read.getSample([0n]))

  // const orderId = 81177068471485603709267478311745501823984771275353499276050752082067293470721n
  // const bookId = orderId >> 64n
  // const tick = (orderId >> 40n) & 0xffffffn
  // // await sc.write.addOrder([bookId, Number(tick), zeroAddress, 0x123123123n])
  // // await sc.write.addOrder([bookId, Number(tick), zeroAddress, 0x444444444n])
  // const key = keccak256(
  //   encodeAbiParameters(
  //     [
  //       { name: 'x', type: 'uint192' },
  //       { name: 'y', type: 'uint256' },
  //     ],
  //     [bookId, 0n],
  //   ),
  // )
  // const queuesKey = BigInt(key) + 3n
  // const queueKey = keccak256(
  //   encodeAbiParameters(
  //     [
  //       { name: 'tick', type: 'uint256' },
  //       { name: 'k', type: 'uint256' },
  //     ],
  //     [tick, queuesKey],
  //   ),
  // )
  // console.log(key, await sc.read.load([key, 3n]))
  // const orderKey = keccak256(encodeAbiParameters([{ name: 'k', type: 'uint256' }], [BigInt(queueKey) + 4n]))
  // console.log(bigintToBytes32(BigInt(queueKey) + 4n), await sc.read.load([bigintToBytes32(BigInt(queueKey) + 4n)]))
  // console.log(orderKey, await sc.read.load([orderKey]))
  // console.log(bigintToBytes32(BigInt(orderKey) + 1n), await sc.read.load([bigintToBytes32(BigInt(orderKey) + 1n)]))
  //
  // console.log(await sc.read.getSlot([orderId]))
  // console.log(await sc.read.decode([orderId]))
  // console.log(await sc.read.getOrder4([orderId]))
  // console.log(await sc.read.getOrder5([orderId]))
  // console.log(await sc.read.getOrder3([orderId]))
  // console.log(await sc.read.getOrder2([orderId]))
  // console.log(await sc.read.getOrder([orderId]))

  // const key = 1234n
  // const packKey = 333n
  // const addr = '0x7f5f96a0EA27624D1aA027B28DC061EeADf89ef7'
  // const num = 0x123123000n
  // console.log('getSlots', await sc.read.getSlots([key, packKey]))
  // console.log('length', await sc.read.length([key, packKey]))
  // const res = await sc.write.addSample([key, packKey, addr, num])
  // console.log(res)
  // console.log('length', await sc.read.length([key, packKey]))
  // console.log('getSample', await sc.read.getSample([key, packKey, 0n]))
})

const bigintToBytes32 = (num: bigint): Hex => {
  return `0x${num.toString(16).padStart(64, '0')}`
}
