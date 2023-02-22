const {
  TREASURY_ADDRESS,
  AUCTION,
  MARKETPLACE,
  BUNDLE_MARKETPLACE,
} = require("./constants");

async function main() {
  const NFTTradable = await ethers.getContractFactory("NiftyNFTTradable");
  const nft = await NFTTradable.deploy(
    "Artion",
    "ART",
    AUCTION,
    MARKETPLACE,
    BUNDLE_MARKETPLACE,
    "10000000000000000000",
    TREASURY_ADDRESS,
    false,
    "0x0000000000000000000000000000000000000000"
  );
  await nft.deployed();
  console.log("NiftyNFTTradable deployed at:", nft.address);

  // const NFTTradablePrivate = await ethers.getContractFactory(
  //   'NiftyNFTTradablePrivate'
  // );
  // const nftPrivate = await NFTTradablePrivate.deploy(
  //   'IArtion',
  //   'IART',
  //   AUCTION,
  //   MARKETPLACE,
  //   BUNDLE_MARKETPLACE,
  //   '10000000000000000000',
  //   TREASURY_ADDRESS
  // );
  // await nftPrivate.deployed();
  // console.log('NiftyNFTTradablePrivate deployed at:', nftPrivate.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
