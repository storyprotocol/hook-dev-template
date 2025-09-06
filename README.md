# Hook Template: `LockLicenseHook.sol`

This is a template repository meant to show developers how to write and test their own license hooks on [Story](https://docs.story.foundation). This template uses `LockLicenseHook.sol` as an example, which is the most basic form of a license hook that lets you stop/lock license minting.

## Quick Start

### Prerequisites

Please install [Foundry / Foundryup](https://github.com/gakonst/foundry)

### Install dependencies

```sh
yarn # this installs packages
forge build # this builds
```

### Run the Tests

Run this script to run a live forked test on Aeneid (Story testnet)

```
forge test --fork-url https://aeneid.storyrpc.io/
```
