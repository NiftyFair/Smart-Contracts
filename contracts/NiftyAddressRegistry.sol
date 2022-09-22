// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NiftyAddressRegistry is Ownable {
    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    /// @notice Artion contract
    address public artion;

    /// @notice NiftyAuction contract
    address public auction;

    /// @notice NiftyMarketplace contract
    address public marketplace;

    /// @notice NiftyBundleMarketplace contract
    address public bundleMarketplace;

    /// @notice NiftyNFTFactory contract
    address public factory;

    /// @notice NiftyNFTFactoryPrivate contract
    address public privateFactory;

    /// @notice NiftyArtFactory contract
    address public artFactory;

    /// @notice NiftyArtFactoryPrivate contract
    address public privateArtFactory;

    /// @notice NiftyTokenRegistry contract
    address public tokenRegistry;

    /// @notice NiftyPriceFeed contract
    address public priceFeed;

    /// @notice NiftyRoyaltyRegistry contract
    address public royaltyRegistry;

    /**
     @notice Update artion contract
     @dev Only admin
     */
    function updateArtion(address _artion) external onlyOwner {
        require(
            IERC165(_artion).supportsInterface(INTERFACE_ID_ERC721),
            "Not ERC721"
        );
        artion = _artion;
    }

    /**
     @notice Update NiftyAuction contract
     @dev Only admin
     */
    function updateAuction(address _auction) external onlyOwner {
        auction = _auction;
    }

    /**
     @notice Update NiftyMarketplace contract
     @dev Only admin
     */
    function updateMarketplace(address _marketplace) external onlyOwner {
        marketplace = _marketplace;
    }

    /**
     @notice Update NiftyBundleMarketplace contract
     @dev Only admin
     */
    function updateBundleMarketplace(address _bundleMarketplace)
        external
        onlyOwner
    {
        bundleMarketplace = _bundleMarketplace;
    }

    /**
     @notice Update NiftyNFTFactory contract
     @dev Only admin
     */
    function updateNFTFactory(address _factory) external onlyOwner {
        factory = _factory;
    }

    /**
     @notice Update NiftyNFTFactoryPrivate contract
     @dev Only admin
     */
    function updateNFTFactoryPrivate(address _privateFactory)
        external
        onlyOwner
    {
        privateFactory = _privateFactory;
    }

    /**
     @notice Update NiftyArtFactory contract
     @dev Only admin
     */
    function updateArtFactory(address _artFactory) external onlyOwner {
        artFactory = _artFactory;
    }

    /**
     @notice Update NiftyArtFactoryPrivate contract
     @dev Only admin
     */
    function updateArtFactoryPrivate(address _privateArtFactory)
        external
        onlyOwner
    {
        privateArtFactory = _privateArtFactory;
    }

    /**
     @notice Update token registry contract
     @dev Only admin
     */
    function updateTokenRegistry(address _tokenRegistry) external onlyOwner {
        tokenRegistry = _tokenRegistry;
    }

    /**
     @notice Update price feed contract
     @dev Only admin
     */
    function updatePriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = _priceFeed;
    }

    /**
     @notice Update royalty registry contract
     @dev Only admin
     */
    function updateRoyaltyRegistry(address _royaltyRegistry)
        external
        onlyOwner
    {
        royaltyRegistry = _royaltyRegistry;
    }
}
