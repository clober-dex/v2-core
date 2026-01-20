# Clober V2

[![Docs](https://img.shields.io/badge/docs-%F0%9F%93%84-blue)](https://docs.clober.io/)
[![CI status](https://github.com/clober-dex/v2-core/actions/workflows/test.yaml/badge.svg)](https://github.com/clober-dex/v2-core/actions/workflows/test.yaml)
[![Discord](https://img.shields.io/static/v1?logo=discord&label=discord&message=Join&color=blue)](https://discord.com/invite/clober-coupon-finance)
[![Twitter](https://img.shields.io/static/v1?logo=twitter&label=twitter&message=Follow&color=blue)](https://twitter.com/CloberDEX)

Core Contract of Clober DEX V2

## Table of Contents

- [Clober V2](#clober-v2)
    - [Table of Contents](#table-of-contents)
    - [Deployments](#deployments)
    - [Install](#install)
    - [Usage](#usage)
        - [Tests](#tests)
        - [Linting](#linting)
        - [Library](#library)
    - [Licensing](#licensing)

## Deployments

All deployments can be found in the [deployments](./deployments) directory.

### Recent `BookManager` deployments

- **Base (chainId 8453)**: `0x8ca3a6f4a6260661fcb9a25584c796a1fa380112`
- **Arbitrum One (chainId 42161)**: `0x74ffe45757db60b24a7574b3b5948dad368c2fdf`
- **Monad (chainId 143)**: `0x6657d192273731c3cac646cc82d5f28d0cbe8ccc`

## Install

### Prerequisites
- We use [Foundry](https://github.com/foundry-rs/foundry). Follow the [installation guide](https://github.com/foundry-rs/foundry#installation).

### Installing From Source

```bash
git clone https://github.com/clober-dex/v2-core && cd v2-core
forge install
```

## Usage

### Build

```bash
forge build
```

### Tests

```bash
forge test
```

### Formatting

```bash
forge fmt
```

### Library
To utilize the contracts, you can install the code in your repo with forge:
```bash
forge install https://github.com/clober-dex/v2-core
```

## Licensing
- The primary license for Clober Core V2 is the Time-delayed Open Source Software Licence, see [License file](LICENSE_V2.pdf).
- Interfaces are licensed under MIT (as indicated in their SPDX headers).
- Some [libraries](src/libraries) have a GPL license.
