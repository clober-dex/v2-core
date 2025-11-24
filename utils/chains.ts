import { defineChain } from 'viem'

const riseTestnetChainId = 11155931
const monadPrivateMainnetChainId = 143

export const riseTestnet = defineChain({
  name: riseTestnetChainId.toString(),
  id: riseTestnetChainId,
  nativeCurrency: {
    name: 'Ethereum',
    symbol: 'ETH',
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: [process.env.RISE_TESTNET_RPC_URL ?? ''],
    },
  },
})

export const monadPrivateMainnet = defineChain({
  name: monadPrivateMainnetChainId.toString(),
  id: monadPrivateMainnetChainId,
  nativeCurrency: {
    name: 'Monad',
    symbol: 'MON',
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: [process.env.MONAD_MAINNET_RPC_URL ?? ''],
    },
  },
})
