module.exports = {
  norpc: true,
  testCommand: 'npm run test',
  compileCommand: 'npm run compile',
  skipFiles: ['mocks', 'library'],
  providerOptions: {
    default_balance_ether: '10000000000000000000000000',
  },
  mocha: {
    fgrep: '[skip-on-coverage]',
    invert: true,
  },
}
