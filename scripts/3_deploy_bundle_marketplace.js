const {
  TREASURY_ADDRESS,
  PLATFORM_FEE,
  PROXY_ADDRESS_TESTNET,
  PROXY_ADDRESS_MAINNET,
} = require("./constants");

async function main() {
  const Marketplace = await ethers.getContractFactory("NiftyBundleMarketplace");
  const marketplaceImpl = await Marketplace.deploy();
  await marketplaceImpl.deployed();
  console.log("NiftyBundleMarketplace deployed at:", marketplaceImpl.address);

  const AdminUpgradeabilityProxyFactory = await ethers.getContractFactory(
    "AdminUpgradeabilityProxy"
  );

  // Mainnet
  const marketplaceProxy = await AdminUpgradeabilityProxyFactory.deploy(
    marketplaceImpl.address,
    PROXY_ADDRESS_MAINNET,
    []
  );

  // Testnet
  // const marketplaceProxy = await AdminUpgradeabilityProxyFactory.deploy(
  //   marketplaceImpl.address,
  //   PROXY_ADDRESS_TESTNET,
  //   []
  // );

  await marketplaceProxy.deployed();
  console.log(
    "Bundle Marketplace Proxy deployed at ",
    marketplaceProxy.address
  );

  const marketplace = await ethers.getContractAt(
    "NiftyBundleMarketplace",
    marketplaceProxy.address
  );
  await marketplace.initialize(TREASURY_ADDRESS, PLATFORM_FEE);
  console.log("Bundle Marketplace Proxy initialized");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
