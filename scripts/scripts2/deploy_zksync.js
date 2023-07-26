// to deploy locally
// run: npx hardhat node on a terminal
// then run: npx hardhat run  scripts/scripts2/deploy_gc.js --network localhost
// npx hardhat deploy-zksync --script scripts/scripts2/deploy_zksync.js --network zksynctest
async function main(network) {
  console.log("network: ", network.name);

  let payToken;

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deployer's address: `, deployerAddress);

  const {
    ZERO_ADDRESS,
    TREASURY_ADDRESS,
    PLATFORM_FEE,
    PAY_TOKEN_MAINNET,
  } = require("../constants.zksync");

  payToken = PAY_TOKEN_MAINNET;

  console.log("PayToken deployed at: ", payToken);

  ////////////
  const NiftyToken = await ethers.getContractFactory("NiftyToken");
  const niftyToken = await NiftyToken.deploy(
    TREASURY_ADDRESS,
    "2000000000000000000"
  );

  await niftyToken.deployed();
  console.log("NiftyToken deployed at: ", niftyToken.address);
  ///////////

  //////////
  const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin");
  const proxyAdmin = await ProxyAdmin.deploy();
  await proxyAdmin.deployed();

  const PROXY_ADDRESS = proxyAdmin.address;
  console.log("ProxyAdmin deployed at:", proxyAdmin.address);

  const AdminUpgradeabilityProxyFactory = await ethers.getContractFactory(
    "AdminUpgradeabilityProxy"
  );
  //////////

  /////////
  const Marketplace = await ethers.getContractFactory("NiftyMarketplace");
  const marketplaceImpl = await Marketplace.deploy();
  await marketplaceImpl.deployed();

  console.log("NiftyMarketplace deployed at:", marketplaceImpl.address);

  const marketplaceProxy = await AdminUpgradeabilityProxyFactory.deploy(
    marketplaceImpl.address,
    PROXY_ADDRESS,
    []
  );
  await marketplaceProxy.deployed();
  console.log(
    "NiftyMarketplace Proxy deployed at:  ",
    marketplaceProxy.address
  );
  const MARKETPLACE_PROXY_ADDRESS = marketplaceProxy.address;
  const marketplace = await ethers.getContractAt(
    "NiftyMarketplace",
    marketplaceProxy.address
  );

  await marketplace.initialize(TREASURY_ADDRESS, PLATFORM_FEE);
  //   console.log('Marketplace Proxy initialized');

  /////////

  ////////
  const Auction = await ethers.getContractFactory("NiftyAuction");
  const auctionImpl = await Auction.deploy();
  await auctionImpl.deployed();
  console.log("NiftyAuction deployed at:", auctionImpl.address);

  const auctionProxy = await AdminUpgradeabilityProxyFactory.deploy(
    auctionImpl.address,
    PROXY_ADDRESS,
    []
  );

  await auctionProxy.deployed();
  console.log("NiftyAuction Proxy deployed at:  ", auctionProxy.address);
  const AUCTION_PROXY_ADDRESS = auctionProxy.address;
  const auction = await ethers.getContractAt(
    "NiftyAuction",
    auctionProxy.address
  );

  await auction.initialize(TREASURY_ADDRESS);
  //   console.log('Auction Proxy initialized');

  ////////

  ////////
  const TokenRegistry = await ethers.getContractFactory("NiftyTokenRegistry");
  const tokenRegistry = await TokenRegistry.deploy();

  await tokenRegistry.deployed();

  console.log("NiftyTokenRegistry deployed at:", tokenRegistry.address);
  ////////

  ////////
  const AddressRegistry = await ethers.getContractFactory(
    "NiftyAddressRegistry"
  );
  const addressRegistry = await AddressRegistry.deploy();

  await addressRegistry.deployed();

  console.log("NiftyAddressRegistry deployed at:", addressRegistry.address);
  const NIFTYFAIR_ADDRESS_REGISTRY = addressRegistry.address;
  ////////

  ////////
  const PriceFeed = await ethers.getContractFactory("NiftyPriceFeed");
  const PAY_TOKEN = payToken;
  const priceFeed = await PriceFeed.deploy(
    NIFTYFAIR_ADDRESS_REGISTRY,
    PAY_TOKEN
  );

  await priceFeed.deployed();
  console.log("NiftyPriceFeed deployed at:", priceFeed.address);
  ////////

  ////////
  const RoyaltyRegistry = await ethers.getContractFactory(
    "NiftyRoyaltyRegistry"
  );
  const royaltyRegistery = await RoyaltyRegistry.deploy();

  await royaltyRegistery.deployed();

  console.log("NiftyRoyaltyRegistry deployed at:", royaltyRegistery.address);

  ////////

  await marketplace.updateAddressRegistry(NIFTYFAIR_ADDRESS_REGISTRY);
  await auction.updateAddressRegistry(NIFTYFAIR_ADDRESS_REGISTRY);

  await addressRegistry.updateArtion(niftyToken.address);

  await addressRegistry.updateAuction(auction.address);
  await addressRegistry.updateMarketplace(marketplace.address);

  await addressRegistry.updateTokenRegistry(tokenRegistry.address);
  await addressRegistry.updatePriceFeed(priceFeed.address);

  await addressRegistry.updateRoyaltyRegistry(royaltyRegistery.address);

  await tokenRegistry.add(PAY_TOKEN);

  console.log("ADD PRICE ORACLE");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main(network)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
