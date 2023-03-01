# Smart contracts for the NiftyFair Marketplace

## Installing

Run npm install

```
npm i
```

## Running tests

1. Run a Hardhat node:

```
npm run node
```

2. Start the tests in another terminal:

```
npm run test
```

3. After each test run, please restart the node.

## Flatten contracts

Use the following command to flatten a single file:

```
npx hardhat flatten contracts/NiftyMarketplace.sol > flatten/NiftyMarketplace.sol
```

Keep only one SPDX license file in the flattened contract
