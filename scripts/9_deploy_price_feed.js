const {
  NIFTYFAIR_ADDRESS_REGISTRY,
  PAY_TOKEN_MAINNET,
} = require('./constants');

async function main() {
  const Contract = await ethers.getContractFactory('NiftyPriceFeed');
  const contract = await Contract.deploy(
    NIFTYFAIR_ADDRESS_REGISTRY,
    PAY_TOKEN_MAINNET
  );

  await contract.deployed();

  console.log('NiftyPriceFeed deployed to', contract.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
