// This part of the test is used to set-up the basic environment for testing the `NiftyAuction`
// smart contract. This will be run before each individual test as part of the `before()` function

const { ethers } = require('hardhat');

const { ONE, mockPayTokenMintAmount } = require('./index_ethers.js');

async function callBefore() {
  [owner, bidder, seller, winner, hacker, other, royaltyMigrationManager] =
    await ethers.getSigners();
  // Mint MockERC20 tokens to users in the unit test
  await mockerc20.connect(owner).mintPay(owner.address, mockPayTokenMintAmount);
  await mockerc20
    .connect(owner)
    .mintPay(bidder.address, mockPayTokenMintAmount);
  await mockerc20
    .connect(owner)
    .mintPay(seller.address, mockPayTokenMintAmount);
  await mockerc20
    .connect(owner)
    .mintPay(winner.address, mockPayTokenMintAmount);
  await mockerc20.connect(owner).mintPay(other.address, mockPayTokenMintAmount);

  // Approve the NiftyAuction contract to transfer MockERC20 tokens
  await mockerc20
    .connect(owner)
    .approve(niftyfairauction.address, mockPayTokenMintAmount);
  await mockerc20
    .connect(bidder)
    .approve(niftyfairauction.address, mockPayTokenMintAmount);
  await mockerc20
    .connect(seller)
    .approve(niftyfairauction.address, mockPayTokenMintAmount);
  await mockerc20
    .connect(winner)
    .approve(niftyfairauction.address, mockPayTokenMintAmount);
  await mockerc20
    .connect(other)
    .approve(niftyfairauction.address, mockPayTokenMintAmount);
  await mockerc20
    .connect(hacker)
    .approve(niftyfairauction.address, mockPayTokenMintAmount);

  // Mints MockERC721 tokens to users
  await mockerc721.connect(owner).mint(owner.address);
  await mockerc721.connect(owner).mint(seller.address);
  await mockerc721.connect(owner).mint(seller.address);
  await mockerc721.connect(owner).mint(seller.address);
  await mockerc721.connect(owner).mint(seller.address);
  await mockerc721.connect(owner).mint(seller.address);
  await mockerc721.connect(owner).mint(other.address);
  await mockerc721.connect(owner).mint(other.address);
  await mockerc721.connect(owner).mint(other.address);
  await mockerc721.connect(owner).mint(other.address);

  // Sets approvals for NiftyAuction to transfer MockERC721 tokens
  await mockerc721
    .connect(owner)
    .setApprovalForAll(niftyfairauction.address, true);
  await mockerc721
    .connect(bidder)
    .setApprovalForAll(niftyfairauction.address, true);
  await mockerc721
    .connect(seller)
    .setApprovalForAll(niftyfairauction.address, true);
  await mockerc721
    .connect(winner)
    .setApprovalForAll(niftyfairauction.address, true);
  await mockerc721
    .connect(other)
    .setApprovalForAll(niftyfairauction.address, true);
  await mockerc721
    .connect(hacker)
    .setApprovalForAll(niftyfairauction.address, true);

  // Initializes `NiftyAuction`, `NiftyBundleMarketplace`, and `NiftyMarketplace`
  await niftyfairauction.connect(owner).initialize(owner.address);
  await niftyfairbundlemarketplace.connect(owner).initialize(owner.address, ONE);
  await niftyfairmarketplace.connect(owner).initialize(owner.address, ONE);

  // Updates all addresses in/for `NiftyAddressRegistry`
  await niftyfairaddressregistry.connect(owner).updateArtion(niftyfairartion.address);
  await niftyfairaddressregistry
    .connect(owner)
    .updateAuction(niftyfairauction.address);
  await niftyfairaddressregistry
    .connect(owner)
    .updateMarketplace(niftyfairmarketplace.address);
  await niftyfairaddressregistry
    .connect(owner)
    .updateBundleMarketplace(niftyfairbundlemarketplace.address);
  await niftyfairaddressregistry
    .connect(owner)
    .updateTokenRegistry(niftyfairtokenregistry.address);
  await niftyfairaddressregistry
    .connect(owner)
    .updateRoyaltyRegistry(niftyfairRoyaltyRegistry.address);
  await niftyfairaddressregistry
    .connect(owner)
    .updatePriceFeed(niftyfairPriceFeed.address);
  await niftyfairauction
    .connect(owner)
    .updateAddressRegistry(niftyfairaddressregistry.address);
  await niftyfairmarketplace
    .connect(owner)
    .updateAddressRegistry(niftyfairaddressregistry.address);
  await niftyfairbundlemarketplace
    .connect(owner)
    .updateAddressRegistry(niftyfairaddressregistry.address);

  // Adds the MockERC20 token to the `NiftyTokenRegistry`
  await niftyfairtokenregistry.connect(owner).add(mockerc20.address);

  await niftyfairRoyaltyRegistry
    .connect(owner)
    .updateMigrationManager(royaltyMigrationManager.address);

  await niftyfairPriceFeed
    .connect(owner)
    .registerOracle(mockerc20.address, mockPriceOracleProxy.address);
}

module.exports = {
  callBefore
};
