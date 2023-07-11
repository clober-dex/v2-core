import { expect } from 'chai'
import hre from 'hardhat'

import { Greeter } from '../typechain'
import { getDeployedContract } from '../utils/misc'

const { deployments, network } = hre

describe('Greeter', () => {
  let Greeter: Greeter
  beforeEach(async () => {
    network.provider.emit('hardhatNetworkReset')
    await deployments.fixture(['Greeter'])

    Greeter = await getDeployedContract<Greeter>('Greeter')
  })

  it("should return the new greeting once it's changed", async () => {
    expect(await Greeter.greet()).to.equal('Hello, solidity!')

    const setGreetingTx = await Greeter.setGreeting('Hola, mundo!')

    // wait until the transaction is mined
    await setGreetingTx.wait()

    expect(await Greeter.greet()).to.equal('Hola, mundo!')
  })
})
