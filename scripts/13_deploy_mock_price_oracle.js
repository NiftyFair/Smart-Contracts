async function main() {
    const RoyaltyRegistry = await ethers.getContractFactory(
      'NiftyPriceOracle'
    );
    const contract = await RoyaltyRegistry.deploy();
  
    await contract.deployed();
  
    console.log('NiftyPriceOracle deployed to', contract.address);
  }
  
  // We recommend this pattern to be able to use async/await everywhere
  // and properly handle errors.
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });