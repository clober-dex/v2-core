# Template contract project

## Usage
#### 1. Network Config
You should set your network config on [hardhat.config.ts](./hardhat.config.ts) and [constant.ts](./utils/constant.ts)
- [hardhat Configuration](https://hardhat.org/hardhat-runner/docs/config)
- [EVM Chainlist](https://chainlist.org/)

#### 2. Private key setting
If you want to deploy the contract through the private key of EOA, refer to the `.env.example` file and insert `process.env.PRIVATE_KEY` into the `accounts` key.
Or, if you want to deploy through a json file, move the json to the root folder with the name `./mainnet-deploy-key-store.json`.

#### 3. Deploy contracts
We use [hardhat-deploy](https://github.com/wighawag/hardhat-deploy) to manage our deployments.
If you want to deploy [`Greeter` Contract](contracts/Greeter.sol), run command:
```shell
$ npx hardhat deploy --network localhost --tags Greeter

```

#### 4. Generate typechain
After deploying to hardhat with this command:
- `share` folder is only filter ABIs excluding source code.
- `share-typechain` folder is typechain scripts.
```shell
$ npm run deployments:update

deployments
├── localhost
│   ├── Greeter.json
│   └── solcInputs
│       └── c5931bdbb8c9e836024a12a6aeb22cf1.json
├── share
│   └── localhost
│       └── Greeter.json
└── share-typechain
    ├── localhost
    │   └── address.json
    └── typechain
        ├── Greeter.ts
        ├── common.ts
        ├── factories
        │   ├── Greeter__factory.ts
        │   └── index.ts
        └── index.ts
```

#### 5. Sync with the latest template code
Run below script to sync with the latest template.
```shell
$ git remote add template git@[Your Id]:clober-dex/clober-solidity-template.git
$ git fetch --all
$ git merge template/[branch] --allow-unrelated-histories
```

#### etc. If you want to use `pre-commit`
```shell
$ pip install pre-commit
$ pre-commit install # use automatically `pre-commit`
```
