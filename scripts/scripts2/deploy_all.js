// to deploy locally
// run: npx hardhat node on a terminal
// then run: npx hardhat run --network localhost scripts/12_deploy_all.js
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
  } = require("../constants");

  if (network.name === "mainnet") {
    payToken = PAY_TOKEN_MAINNET;
  }

  if (network.name === "localhost") {
    const WXDAI = await ethers.getContractFactory("WXDAI");
    const wrappedXDAI = await WXDAI.deploy();

    payToken = await wrappedXDAI.address;
  }

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

  /////////
  const BundleMarketplace = await ethers.getContractFactory(
    "NiftyBundleMarketplace"
  );
  const bundleMarketplaceImpl = await BundleMarketplace.deploy();
  await bundleMarketplaceImpl.deployed();
  console.log(
    "NiftyBundleMarketplace deployed at:",
    bundleMarketplaceImpl.address
  );

  const bundleMarketplaceProxy = await AdminUpgradeabilityProxyFactory.deploy(
    bundleMarketplaceImpl.address,
    PROXY_ADDRESS,
    []
  );
  await bundleMarketplaceProxy.deployed();
  console.log(
    "Bundle Marketplace Proxy deployed at ",
    bundleMarketplaceProxy.address
  );
  const BUNDLE_MARKETPLACE_PROXY_ADDRESS = bundleMarketplaceProxy.address;
  const bundleMarketplace = await ethers.getContractAt(
    "NiftyBundleMarketplace",
    bundleMarketplaceProxy.address
  );

  await bundleMarketplace.initialize(TREASURY_ADDRESS, PLATFORM_FEE);
  //   console.log('Bundle Marketplace Proxy initialized');

  ////////

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
  const Factory = await ethers.getContractFactory("NiftyNFTFactory");
  const factory = await Factory.deploy(
    AUCTION_PROXY_ADDRESS,
    MARKETPLACE_PROXY_ADDRESS,
    BUNDLE_MARKETPLACE_PROXY_ADDRESS,
    "10000000000000000000",
    TREASURY_ADDRESS,
    "50000000000000000000"
  );
  await factory.deployed();
  console.log("NiftyNFTFactory deployed at:", factory.address);

  const PrivateFactory = await ethers.getContractFactory(
    "NiftyNFTFactoryPrivate"
  );
  const privateFactory = await PrivateFactory.deploy(
    AUCTION_PROXY_ADDRESS,
    MARKETPLACE_PROXY_ADDRESS,
    BUNDLE_MARKETPLACE_PROXY_ADDRESS,
    "10000000000000000000",
    TREASURY_ADDRESS,
    "50000000000000000000"
  );
  await privateFactory.deployed();
  console.log("NiftyNFTFactoryPrivate deployed at:", privateFactory.address);
  ////////

  ////////
  const NFTTradable = await ethers.getContractFactory("NiftyNFTTradable");
  const nft = await NFTTradable.deploy(
    "NiftyToken",
    "NFT",
    AUCTION_PROXY_ADDRESS,
    MARKETPLACE_PROXY_ADDRESS,
    BUNDLE_MARKETPLACE_PROXY_ADDRESS,
    "10000000000000000000",
    TREASURY_ADDRESS,
    false,
    ZERO_ADDRESS
  );
  await nft.deployed();
  console.log("NiftyNFTTradable deployed at:", nft.address);

  const NFTTradablePrivate = await ethers.getContractFactory(
    "NiftyNFTTradablePrivate"
  );
  const nftPrivate = await NFTTradablePrivate.deploy(
    "IArtion",
    "IART",
    AUCTION_PROXY_ADDRESS,
    MARKETPLACE_PROXY_ADDRESS,
    BUNDLE_MARKETPLACE_PROXY_ADDRESS,
    "10000000000000000000",
    TREASURY_ADDRESS
  );
  await nftPrivate.deployed();
  console.log("NiftyNFTTradablePrivate deployed at:", nftPrivate.address);
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
  const ArtTradable = await ethers.getContractFactory("NiftyArtTradable");
  const artTradable = await ArtTradable.deploy(
    "NiftyFairArt",
    "FART",
    "20000000000000000000",
    TREASURY_ADDRESS,
    MARKETPLACE_PROXY_ADDRESS,
    BUNDLE_MARKETPLACE_PROXY_ADDRESS
  );
  await artTradable.deployed();
  console.log("NiftyArtTradable deployed at:", artTradable.address);

  const ArtTradablePrivate = await ethers.getContractFactory(
    "NiftyArtTradablePrivate"
  );
  const artTradablePrivate = await ArtTradablePrivate.deploy(
    "NiftyFairArt",
    "FART",
    "20000000000000000000",
    TREASURY_ADDRESS,
    MARKETPLACE_PROXY_ADDRESS,
    BUNDLE_MARKETPLACE_PROXY_ADDRESS
  );
  await artTradablePrivate.deployed();
  console.log(
    "NiftyArtTradablePrivate deployed at:",
    artTradablePrivate.address
  );
  ////////

  ////////
  const ArtFactory = await ethers.getContractFactory("NiftyArtFactory");
  const artFactory = await ArtFactory.deploy(
    MARKETPLACE_PROXY_ADDRESS,
    BUNDLE_MARKETPLACE_PROXY_ADDRESS,
    "20000000000000000000",
    TREASURY_ADDRESS,
    "10000000000000000000"
  );
  await artFactory.deployed();
  console.log("NiftyArtFactory deployed at:", artFactory.address);

  const ArtFactoryPrivate = await ethers.getContractFactory(
    "NiftyArtFactoryPrivate"
  );
  const artFactoryPrivate = await ArtFactoryPrivate.deploy(
    MARKETPLACE_PROXY_ADDRESS,
    BUNDLE_MARKETPLACE_PROXY_ADDRESS,
    "20000000000000000000",
    TREASURY_ADDRESS,
    "10000000000000000000"
  );
  await artFactoryPrivate.deployed();
  console.log("NiftyArtFactoryPrivate deployed at:", artFactoryPrivate.address);
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
  await bundleMarketplace.updateAddressRegistry(NIFTYFAIR_ADDRESS_REGISTRY);
  await auction.updateAddressRegistry(NIFTYFAIR_ADDRESS_REGISTRY);

  await addressRegistry.updateArtion(niftyToken.address);

  await addressRegistry.updateAuction(auction.address);
  await addressRegistry.updateMarketplace(marketplace.address);
  await addressRegistry.updateBundleMarketplace(bundleMarketplace.address);

  await addressRegistry.updateNFTFactory(factory.address);
  await addressRegistry.updateNFTFactoryPrivate(privateFactory.address);

  await addressRegistry.updateTokenRegistry(tokenRegistry.address);
  await addressRegistry.updatePriceFeed(priceFeed.address);

  await addressRegistry.updateArtFactory(artFactory.address);
  await addressRegistry.updateArtFactoryPrivate(artFactoryPrivate.address);

  await addressRegistry.updateRoyaltyRegistry(royaltyRegistery.address);

  await tokenRegistry.add(PAY_TOKEN);

  if (network.name === "localhost") {
    console.log("ADD PRICE ORACLE FOR TEST");
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main(network)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
