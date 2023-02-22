const { TREASURY_ADDRESS } = require("./constants");

async function main() {
  const Auction = await ethers.getContractFactory("NiftyAuction");
  const auctionImpl = await Auction.deploy();
  await auctionImpl.deployed();
  console.log("NiftyAuction deployed at:", auctionImpl.address);

  /*
  const AdminUpgradeabilityProxyFactory = await ethers.getContractFactory(
    'AdminUpgradeabilityProxy'
  );

  const auctionProxy = await AdminUpgradeabilityProxyFactory.deploy(
    auctionImpl.address,
    '0x40940855f6437bEC42a04167AD10FA993250D99C',
    []
  );

  await auctionProxy.deployed();
  console.log('Auction Proxy deployed at ', auctionProxy.address);

  const auction = await ethers.getContractAt(
    'NiftyAuction',
    auctionProxy.address
  );
  await auction.initialize(TREASURY_ADDRESS);
  console.log('Auction Proxy initialized');
  */
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
