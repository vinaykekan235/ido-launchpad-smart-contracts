# ido-launchpad-smart-contracts
A Solidity-based IDO launchpad repository for creating and managing token launch pools on BSC-compatible networks.

## Project description
This repository contains smart contracts, deployment configuration, and support files for an IDO launchpad. The system is built with Truffle and Solidity,and it supports:

- Creating launch pools for token sales
- Managing token deposits and lockups
- Verifying contracts with Etherscan/BscScan via `truffle-plugin-verify`
- Using a secure mnemonic and API key from a local `.secret` file

## Features
- `IDOFactory.sol` / `IDOPool.sol`: factory and pool contracts for launching IDO campaigns
- `TokenLocker.sol` / `TokenLockerFactory.sol`: token lock and release scheduling
- `IDOERC20Pool.sol`: ERC20-based pool support for raised funds and token distribution
- `FeeToken.sol`: token logic for fee or reward distribution
- `truffle-config.js`: network and verification configuration with secret-based credentials

## Secret configuration
Create a `.secret` file in the project root with the following values:

```text
ETHERSCAN_API=your-etherscan-api-key
MNEMONIC=your twelve word wallet mnemonic phrase
```

The project already ignores `.secret` in `.gitignore`, so your private keys and API keys will not be committed.

`truffle-config.js` reads `MNEMONIC` and `ETHERSCAN_API` from `.secret` automatically.

## Compile and use
1. Install dependencies:
   ```bash
   npm install
   ```
2. Compile contracts:
   ```bash
   npx truffle compile
   ```
3. Deploy to a network:
   ```bash
   npx truffle migrate --network bsc_testnet
   ```

> Copy `.secret.example` to `.secret` and fill in your real values before deploying.
