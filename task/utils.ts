import { task } from 'hardhat/config'

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
