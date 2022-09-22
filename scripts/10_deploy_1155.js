const {
  TREASURY_ADDRESS,
  MARKETPLACE,
  BUNDLE_MARKETPLACE
} = require('./constants');

async function main() {
  const ArtTradable = await ethers.getContractFactory('NiftyArtTradable');
  const nft = await ArtTradable.deploy(
    'NiftyFairArt',
    'FART',
    '20000000000000000000',
    TREASURY_ADDRESS,
    MARKETPLACE,
    BUNDLE_MARKETPLACE
  );
  await nft.deployed();
  console.log('NiftyArtTradable deployed to:', nft.address);

  const ArtTradablePrivate = await ethers.getContractFactory(
    'NiftyArtTradablePrivate'
  );
  const nftPrivate = await ArtTradablePrivate.deploy(
    'NiftyFairArt',
    'FART',
    '20000000000000000000',
    TREASURY_ADDRESS,
    MARKETPLACE,
    BUNDLE_MARKETPLACE
  );
  await nftPrivate.deployed();
  console.log('NiftyArtTradablePrivate deployed to:', nftPrivate.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
