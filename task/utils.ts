import { task } from 'hardhat/config'

task('utils:accounts', 'Prints the list of accounts').setAction(
  async (taskArgs, hre) => {
    const accounts = await hre.ethers.getSigners()

    for (const account of accounts) {
      console.log(account.address)
    }
  },
)

task('utils:get-block', 'Print latest block')
  .addOptionalParam('where', 'block hash or block tag', 'latest')
  .setAction(async (taskArgs, hre) => {
    const block = await hre.ethers.provider.getBlock(taskArgs.where)
    console.log(block)
  })
