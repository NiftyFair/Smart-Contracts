async function main() {
  const RoyaltyRegistry = await ethers.getContractFactory(
    'NiftyRoyaltyRegistry'
  );
  const royaltyRegistery = await RoyaltyRegistry.deploy();

  await royaltyRegistery.deployed();

  console.log('NiftyRoyaltyRegistry deployed to', royaltyRegistery.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
