// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./library/ERC2981PerTokenRoyalties.sol";

/**
 * @title NiftyNFTTradable
 * NiftyNFTTradable - ERC721 contract that whitelists a trading address, and has minting functionality.
 */
contract NiftyNFTTradable is
    ERC721URIStorage,
    ERC2981PerTokenRoyalties,
    Ownable
{
    using SafeMath for uint256;

    /// @dev Events of the contract
    event Minted(
        uint256 tokenId,
        address beneficiary,
        string tokenUri,
        address minter
    );
    event UpdatePlatformFee(uint256 platformFee);
    event UpdateFeeRecipient(address payable feeRecipient);
    event UpdateTradableManager(address tradableManager);

    address auction;
    address marketplace;
    address bundleMarketplace;
    uint256 private _currentTokenId = 0;

    bool public isPrivate;

    /// @notice Platform fee
    uint256 public platformFee;

    /// @notice Platform fee receipient
    address payable public feeReceipient;

    /// @notice tradableManager;
    address public tradableManager;

    /// @notice Contract constructor
    constructor(
        string memory _name,
        string memory _symbol,
        address _auction,
        address _marketplace,
        address _bundleMarketplace,
        uint256 _platformFee,
        address payable _feeReceipient,
        bool _isPrivate,
        address _tradableManager
    ) public ERC721(_name, _symbol) {
        auction = _auction;
        marketplace = _marketplace;
        bundleMarketplace = _bundleMarketplace;
        platformFee = _platformFee;
        feeReceipient = _feeReceipient;
        isPrivate = _isPrivate;

        if (isPrivate) {
            require(_tradableManager != address(0), "invalid address");
            tradableManager = _tradableManager;
        }
    }

    modifier onlyAuthorised() {
        if (isPrivate) {
            require(_msgSender() == tradableManager, "not authorized");
        }
        _;
    }

    /**
     @notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint256 the platform fee to set
     */
    function updatePlatformFee(uint256 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    /**
     @notice Method for updating platform fee address
     @dev Only admin
     @param _feeReceipient payable address the address to sends the funds to
     */
    function updateFeeRecipient(address payable _feeReceipient)
        external
        onlyOwner
    {
        feeReceipient = _feeReceipient;
        emit UpdateFeeRecipient(_feeReceipient);
    }

    /**
     @notice Method for updating tradable manager address
     @dev Only admin
     @param _tradableManager address that is allowed to mint (if the collection is private)
     */
    function updateTradableManager(address _tradableManager)
        external
        onlyOwner
    {
        tradableManager = _tradableManager;
        emit UpdateTradableManager(_tradableManager);
    }

    /**
     * @dev Mints a token to an address with a tokenURI.
     * @param _to address of the future owner of the token
     */
    function mint(
        address _to,
        string calldata _tokenUri,
        address _royaltyRecipient,
        uint256 _royaltyValue
    ) external payable onlyAuthorised {
        require(msg.value >= platformFee, "Insufficient funds to mint.");

        uint256 newTokenId = _getNextTokenId();
        _safeMint(_to, newTokenId);
        _setTokenURI(newTokenId, _tokenUri);
        _incrementTokenId();

        //set royalty
        if (_royaltyValue > 0) {
            _setTokenRoyalty(newTokenId, _royaltyRecipient, _royaltyValue);
        }

        // Send funds fee to fee recipient
        (bool success, ) = feeReceipient.call{value: msg.value}("");
        require(success, "Transfer failed");

        emit Minted(newTokenId, _to, _tokenUri, _msgSender());
    }

    /**
    @notice Burns a DigitalaxGarmentNFT, releasing any composed 1155 tokens held by the token itself
    @dev Only the owner or an approved sender can call this method
    @param _tokenId the token ID to burn
    */
    function burn(uint256 _tokenId) external {
        address operator = _msgSender();
        require(
            ownerOf(_tokenId) == operator || isApproved(_tokenId, operator),
            "Only owner or approved"
        );

        // Destroy token mappings
        _burn(_tokenId);
    }


    // Set collection-wide default royalty.
    function setRoyalty(address _receiver, uint16 _royaltyPercent) external override onlyOwner {
        _setRoyalty(_receiver, _royaltyPercent);
    }

    // Set royalty for the given token.
    function setTokenRoyalty(uint256 _tokenId, address _receiver, uint16 _royaltyPercent) external override {
        // only token owner can make the change
        address operator = _msgSender();
        require(ownerOf(_tokenId) == operator || isApproved(_tokenId, operator), "Only owner or approved");

        _setTokenRoyalty(_tokenId, _receiver, _royaltyPercent);
    }

    /**
     * @dev calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId.add(1);
    }

    /**
     * @dev increments the value of _currentTokenId
     */
    function _incrementTokenId() private {
        _currentTokenId++;
    }

    /**
     * @dev checks the given token ID is approved either for all or the single token ID
     */
    function isApproved(uint256 _tokenId, address _operator)
        public
        view
        returns (bool)
    {
        return
            isApprovedForAll(ownerOf(_tokenId), _operator) ||
            getApproved(_tokenId) == _operator;
    }

    /**
     * Override isApprovedForAll to whitelist NiftyFair contracts to enable gas-less listings.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        override
        returns (bool)
    {
        // Whitelist NiftyFair auction, marketplace, bundle marketplace contracts for easy trading.
        if (
            auction == operator ||
            marketplace == operator ||
            bundleMarketplace == operator
        ) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

    /**
     * Override _isApprovedOrOwner to whitelist NiftyFair contracts to enable gas-less listings.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        override
        returns (bool)
    {
        require(
            _exists(tokenId),
            "ERC721: operator query for nonexistent token"
        );
        address owner = ERC721.ownerOf(tokenId);
        if (isApprovedForAll(owner, spender)) return true;
        return super._isApprovedOrOwner(spender, tokenId);
    }

    /// @inheritdoc	ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
