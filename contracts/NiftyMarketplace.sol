// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

interface INiftyAddressRegistry {
    function auction() external view returns (address);

    function factory() external view returns (address);

    function tokenRegistry() external view returns (address);

    function priceFeed() external view returns (address);

    function royaltyRegistry() external view returns (address);
}

interface INiftyNFTFactory {
    function exists(address) external view returns (bool);
}

interface INiftyTokenRegistry {
    function enabled(address) external view returns (bool);
}

interface INiftyPriceFeed {
    function wXDAI() external view returns (address);

    function getPrice(address) external view returns (int256, uint8);
}

interface INiftyRoyaltyRegistry {
    function royaltyInfo(
        address _collection,
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (address, uint256);
}

contract NiftyMarketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using AddressUpgradeable for address payable;
    using SafeERC20 for IERC20;

    /// @notice Events for the contract
    event ItemListed(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        address payToken,
        uint256 pricePerItem,
        uint256 startingTime,
        uint256 endingTime
    );
    event ItemSold(
        address indexed seller,
        address indexed buyer,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        address payToken,
        int256 unitPrice,
        uint256 pricePerItem
    );
    event ItemUpdated(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        address payToken,
        uint256 newPrice
    );
    event ItemCanceled(
        address indexed owner,
        address indexed nft,
        uint256 tokenId
    );
    event OfferCreated(
        address indexed creator,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        address payToken,
        uint256 pricePerItem,
        uint256 deadline
    );
    event OfferCanceled(
        address indexed creator,
        address indexed nft,
        uint256 tokenId
    );
    event UpdatePlatformFee(uint16 platformFee);
    event UpdatePlatformFeeRecipient(address payable platformFeeRecipient);

    /// @notice Structure for listed items
    struct Listing {
        uint256 quantity;
        address payToken;
        uint256 pricePerItem;
        uint256 startingTime;
        uint256 endingTime;
    }

    /// @notice Structure for offer
    struct Offer {
        IERC20 payToken;
        uint256 quantity;
        uint256 pricePerItem;
        uint256 deadline;
    }

    struct ListItemParams {
        address nftAddress;
        uint256 tokenId;
        uint256 quantity;
        address payToken;
        uint256 pricePerItem;
        uint256 startingTime;
        uint256 endingTime;
        bytes signature;
    }

    struct CancelListingParams {
        address nftAddress;
        uint256 tokenId;
        bytes signature;
    }

    struct UpdateListingParams {
        address nftAddress;
        uint256 tokenId;
        address payToken;
        uint256 newPrice;
        bytes signature;
    }

    struct BuyItemParams {
        address nftAddress;
        uint256 tokenId;
        address payToken;
        address owner;
        bytes signature;
    }

    struct CreateOfferParams {
        address nftAddress;
        uint256 tokenId;
        IERC20 payToken;
        uint256 quantity;
        uint256 pricePerItem;
        uint256 deadline;
        bytes signature;
    }

    struct CancelOfferParams {
        address nftAddress;
        uint256 tokenId;
        bytes signature;
    }

    struct AcceptOfferParams {
        address nftAddress;
        uint256 tokenId;
        address creator;
        bytes signature;
    }

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

    /// @notice NftAddress -> Token ID -> Owner -> Listing item
    mapping(address => mapping(uint256 => mapping(address => Listing)))
        public listings;

    /// @notice NftAddress -> Token ID -> Offerer -> Offer
    mapping(address => mapping(uint256 => mapping(address => Offer)))
        public offers;

    /// @notice Platform fee
    uint16 public platformFee;

    /// @notice Platform fee receipient
    address payable public feeReceipient;

    /// @notice Address registry
    INiftyAddressRegistry public addressRegistry;

    modifier isListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        require(listing.quantity > 0, "not listed item");
        _;
    }

    modifier notListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        require(listing.quantity == 0, "already listed");
        _;
    }

    modifier validListing(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];

        _validOwner(_nftAddress, _tokenId, _owner, listedItem.quantity);

        require(_getNow() >= listedItem.startingTime, "item not buyable");
        _;
    }

    modifier offerExists(
        address _nftAddress,
        uint256 _tokenId,
        address _creator
    ) {
        Offer memory offer = offers[_nftAddress][_tokenId][_creator];
        require(
            offer.quantity > 0 && offer.deadline > _getNow(),
            "offer not exists or expired"
        );
        _;
    }

    /// @notice Contract initializer
    function initialize(
        address payable _feeRecipient,
        uint16 _platformFee
    ) public initializer {
        platformFee = _platformFee;
        feeReceipient = _feeRecipient;

        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /// @notice Method for listing NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _quantity token amount to list (needed for ERC-1155 NFTs, set as 1 for ERC-721)
    /// @param _payToken Paying token
    /// @param _pricePerItem sale price for each iteam
    /// @param _startingTime scheduling for a future sale
    /// @param _endingTime scheduling for a future sale
    function listItem(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _quantity,
        address _payToken,
        uint256 _pricePerItem,
        uint256 _startingTime,
        uint256 _endingTime
    ) external nonReentrant notListed(_nftAddress, _tokenId, _msgSender()) {
        ListItemParams memory params = ListItemParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            quantity: _quantity,
            payToken: _payToken,
            pricePerItem: _pricePerItem,
            startingTime: _startingTime,
            endingTime: _endingTime,
            signature: bytes("")
        });

        _listItem(params);
    }

    /// @notice Method for listing NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _quantity token amount to list (needed for ERC-1155 NFTs, set as 1 for ERC-721)
    /// @param _payToken Paying token
    /// @param _pricePerItem sale price for each iteam
    /// @param _startingTime scheduling for a future sale
    /// @param _endingTime scheduling for a future sale
    /// @param _signature Signature of sender
    function listItemMeta(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _quantity,
        address _payToken,
        uint256 _pricePerItem,
        uint256 _startingTime,
        uint256 _endingTime,
        bytes memory _signature
    )
        external
        notListed(
            _nftAddress,
            _tokenId,
            _recoverAddressFromSignature(
                keccak256(
                    abi.encodePacked(
                        _nftAddress,
                        _tokenId,
                        _quantity,
                        _payToken,
                        _pricePerItem,
                        _startingTime,
                        _endingTime
                    )
                ),
                _signature
            )
        )
    {
        ListItemParams memory params = ListItemParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            quantity: _quantity,
            payToken: _payToken,
            pricePerItem: _pricePerItem,
            startingTime: _startingTime,
            endingTime: _endingTime,
            signature: _signature
        });

        _listItem(params);
    }

    /// @notice Method for canceling listed NFT
    function cancelListing(
        address _nftAddress,
        uint256 _tokenId
    ) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        CancelListingParams memory params = CancelListingParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            signature: bytes("")
        });

        _cancelListing(params);
    }

    /// @notice Method for canceling listed NFT
    function cancelListingMeta(
        address _nftAddress,
        uint256 _tokenId,
        bytes memory _signature
    )
        external
        nonReentrant
        isListed(
            _nftAddress,
            _tokenId,
            _recoverAddressFromSignature(
                keccak256(abi.encodePacked(_nftAddress, _tokenId)),
                _signature
            )
        )
    {
        CancelListingParams memory params = CancelListingParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            signature: _signature
        });

        _cancelListing(params);
    }

    /// @notice Method for updating listed NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _payToken payment token
    /// @param _newPrice New sale price for each iteam
    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        uint256 _newPrice
    ) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        UpdateListingParams memory params = UpdateListingParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            payToken: _payToken,
            newPrice: _newPrice,
            signature: bytes("")
        });

        _updateListing(params);
    }

    /// @notice Method for updating listed NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _payToken payment token
    /// @param _newPrice New sale price for each iteam
    /// @param _signature Signature of sender
    function updateListingMeta(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        uint256 _newPrice,
        bytes memory _signature
    )
        external
        nonReentrant
        isListed(
            _nftAddress,
            _tokenId,
            _recoverAddressFromSignature(
                keccak256(
                    abi.encodePacked(
                        _nftAddress,
                        _tokenId,
                        _payToken,
                        _newPrice
                    )
                ),
                _signature
            )
        )
    {
        UpdateListingParams memory params = UpdateListingParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            payToken: _payToken,
            newPrice: _newPrice,
            signature: _signature
        });

        _updateListing(params);
    }

    /// @notice Method for buying listed NFT
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    function buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        address _owner
    )
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _owner)
        validListing(_nftAddress, _tokenId, _owner)
    {
        BuyItemParams memory params = BuyItemParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            payToken: _payToken,
            owner: _owner,
            signature: bytes("")
        });

        _buyItem(params);
    }

    /// @notice Method for buying listed NFT
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _signature Signature of sender
    function buyItemMeta(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        address _owner,
        bytes memory _signature
    )
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _owner)
        validListing(_nftAddress, _tokenId, _owner)
    {
        BuyItemParams memory params = BuyItemParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            payToken: _payToken,
            owner: _owner,
            signature: _signature
        });

        _buyItem(params);
    }

    function bulkBuy(
        address[] memory contracts,
        uint256[] memory tokenIds,
        address[] memory payTokens,
        address[] memory tokenOwners
    ) external nonReentrant {
        require(
            contracts.length == tokenIds.length,
            "contracts does not match tokenIds length"
        );

        require(
            contracts.length == payTokens.length,
            "contracts does not match paytokens length"
        );

        require(
            contracts.length == tokenOwners.length,
            "contracts does not match tokenOwners length"
        );

        Listing memory listedItem;

        for (uint256 i = 0; i < contracts.length; i++) {
            listedItem = listings[contracts[i]][tokenIds[i]][tokenOwners[i]];

            require(listedItem.quantity > 0, "not listed item");
            require(_getNow() >= listedItem.startingTime, "item not buyable");
            require(listedItem.payToken == payTokens[i], "invalid pay token");

            _validOwner(
                contracts[i],
                tokenIds[i],
                tokenOwners[i],
                listedItem.quantity
            );

            if (listedItem.endingTime > 0) {
                require(
                    listedItem.endingTime > _getNow(),
                    "item ending time exceeded"
                );
            }

            _buyItem(
                BuyItemParams({
                    nftAddress: contracts[i],
                    tokenId: tokenIds[i],
                    payToken: payTokens[i],
                    owner: tokenOwners[i],
                    signature: bytes("")
                })
            );
        }
    }

    /// @notice Method for offering item
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _payToken Paying token
    /// @param _quantity Quantity of items
    /// @param _pricePerItem Price per item
    /// @param _deadline Offer expiration
    function createOffer(
        address _nftAddress,
        uint256 _tokenId,
        IERC20 _payToken,
        uint256 _quantity,
        uint256 _pricePerItem,
        uint256 _deadline
    ) external nonReentrant {
        CreateOfferParams memory params = CreateOfferParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            payToken: _payToken,
            quantity: _quantity,
            pricePerItem: _pricePerItem,
            deadline: _deadline,
            signature: bytes("")
        });

        _createOffer(params);
    }

    /// @notice Method for offering item
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _payToken Paying token
    /// @param _quantity Quantity of items
    /// @param _pricePerItem Price per item
    /// @param _deadline Offer expiration
    /// @param _signature Signature of sender
    function createOfferMeta(
        address _nftAddress,
        uint256 _tokenId,
        IERC20 _payToken,
        uint256 _quantity,
        uint256 _pricePerItem,
        uint256 _deadline,
        bytes memory _signature
    ) external nonReentrant {
        CreateOfferParams memory params = CreateOfferParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            payToken: _payToken,
            quantity: _quantity,
            pricePerItem: _pricePerItem,
            deadline: _deadline,
            signature: _signature
        });

        _createOffer(params);
    }

    /// @notice Method for canceling the offer
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    function cancelOffer(
        address _nftAddress,
        uint256 _tokenId
    ) external nonReentrant {
        CancelOfferParams memory params = CancelOfferParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            signature: bytes("")
        });

        _cancelOffer(params);
    }

    /// @notice Method for canceling the offer
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _signature Signature of sender
    function cancelOfferMeta(
        address _nftAddress,
        uint256 _tokenId,
        bytes memory _signature
    ) external nonReentrant {
        CancelOfferParams memory params = CancelOfferParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            signature: _signature
        });

        _cancelOffer(params);
    }

    /// @notice Method for accepting the offer
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _creator Offer creator address
    function acceptOffer(
        address _nftAddress,
        uint256 _tokenId,
        address _creator
    ) external nonReentrant offerExists(_nftAddress, _tokenId, _creator) {
        AcceptOfferParams memory params = AcceptOfferParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            creator: _creator,
            signature: bytes("")
        });

        _acceptOffer(params);
    }

    /// @notice Method for accepting the offer
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _creator Offer creator address
    /// @param _signature Signature of sender
    function acceptOfferMeta(
        address _nftAddress,
        uint256 _tokenId,
        address _creator,
        bytes memory _signature
    ) external nonReentrant offerExists(_nftAddress, _tokenId, _creator) {
        AcceptOfferParams memory params = AcceptOfferParams({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            creator: _creator,
            signature: _signature
        });

        _acceptOffer(params);
    }

    /**
     @notice Method for getting price for pay token
     @param _payToken Paying token
     */
    function getPrice(address _payToken) public view returns (int256) {
        int256 unitPrice;
        uint8 decimals;
        INiftyPriceFeed priceFeed = INiftyPriceFeed(
            addressRegistry.priceFeed()
        );

        if (_payToken == address(0)) {
            (unitPrice, decimals) = priceFeed.getPrice(priceFeed.wXDAI());
        } else {
            (unitPrice, decimals) = priceFeed.getPrice(_payToken);
        }
        if (decimals < 18) {
            unitPrice = unitPrice * (int256(10) ** (18 - decimals));
        } else {
            unitPrice = unitPrice / (int256(10) ** (decimals - 18));
        }

        return unitPrice;
    }

    /**
     @notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint16 the platform fee to set
     */
    function updatePlatformFee(uint16 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    /**
     @notice Method for updating platform fee address
     @dev Only admin
     @param _platformFeeRecipient payable address the address to sends the funds to
     */
    function updatePlatformFeeRecipient(
        address payable _platformFeeRecipient
    ) external onlyOwner {
        feeReceipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }

    /**
     @notice Update NiftyAddressRegistry contract
     @dev Only admin
     */
    function updateAddressRegistry(address _registry) external onlyOwner {
        addressRegistry = INiftyAddressRegistry(_registry);
    }

    ////////////////////////////
    /// Internal and Private ///
    ////////////////////////////

    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _validPayToken(address _payToken) internal view {
        require(
            _payToken == address(0) ||
                (addressRegistry.tokenRegistry() != address(0) &&
                    INiftyTokenRegistry(addressRegistry.tokenRegistry())
                        .enabled(_payToken)),
            "invalid pay token"
        );
    }

    function _validOwner(
        address _nftAddress,
        uint256 _tokenId,
        address _owner,
        uint256 quantity
    ) internal view {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _owner, "not owning item");
        } else if (
            IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155)
        ) {
            IERC1155 nft = IERC1155(_nftAddress);
            require(
                nft.balanceOf(_owner, _tokenId) >= quantity,
                "not owning item"
            );
        } else {
            revert("invalid nft address");
        }
    }

    function _listItem(ListItemParams memory params) internal {
        address user;

        if (params.signature.length == 0) {
            user = _msgSender();
        } else {
            user = _recoverAddressFromSignature(
                keccak256(
                    abi.encodePacked(
                        params.nftAddress,
                        params.tokenId,
                        params.quantity,
                        params.payToken,
                        params.pricePerItem,
                        params.startingTime,
                        params.endingTime
                    )
                ),
                params.signature
            );
        }

        if (IERC165(params.nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(params.nftAddress);
            require(nft.ownerOf(params.tokenId) == user, "not owning item");
            require(
                nft.isApprovedForAll(_msgSender(), address(this)),
                "item not approved"
            );
        } else if (
            IERC165(params.nftAddress).supportsInterface(INTERFACE_ID_ERC1155)
        ) {
            IERC1155 nft = IERC1155(params.nftAddress);
            require(
                nft.balanceOf(_msgSender(), params.tokenId) >= params.quantity,
                "must hold enough nfts"
            );
            require(
                nft.isApprovedForAll(_msgSender(), address(this)),
                "item not approved"
            );
        } else {
            revert("invalid nft address");
        }

        _validPayToken(params.payToken);

        listings[params.nftAddress][params.tokenId][_msgSender()] = Listing(
            params.quantity,
            params.payToken,
            params.pricePerItem,
            params.startingTime,
            params.endingTime
        );
        emit ItemListed(
            user,
            params.nftAddress,
            params.tokenId,
            params.quantity,
            params.payToken,
            params.pricePerItem,
            params.startingTime,
            params.endingTime
        );
    }

    function _cancelListing(CancelListingParams memory params) internal {
        address user;
        if (params.signature.length == 0) {
            user = _msgSender();
        } else {
            user = _recoverAddressFromSignature(
                keccak256(abi.encodePacked(params.nftAddress, params.tokenId)),
                params.signature
            );
        }

        Listing memory listedItem = listings[params.nftAddress][params.tokenId][
            user
        ];

        _validOwner(
            params.nftAddress,
            params.tokenId,
            user,
            listedItem.quantity
        );

        delete (listings[params.nftAddress][params.tokenId][user]);
        emit ItemCanceled(user, params.nftAddress, params.tokenId);
    }

    function _updateListing(UpdateListingParams memory params) internal {
        address user;

        if (params.signature.length == 0) {
            user = _msgSender();
        } else {
            user = _recoverAddressFromSignature(
                keccak256(
                    abi.encodePacked(
                        params.nftAddress,
                        params.tokenId,
                        params.payToken,
                        params.newPrice
                    )
                ),
                params.signature
            );
        }

        Listing memory listedItem = listings[params.nftAddress][params.tokenId][
            user
        ];

        _validOwner(
            params.nftAddress,
            params.tokenId,
            user,
            listedItem.quantity
        );

        _validPayToken(params.payToken);

        listedItem.payToken = params.payToken;
        listedItem.pricePerItem = params.newPrice;
        emit ItemUpdated(
            user,
            params.nftAddress,
            params.tokenId,
            params.payToken,
            params.newPrice
        );
    }

    function _buyItem(BuyItemParams memory params) internal {
        address user;

        if (params.signature.length == 0) {
            user = _msgSender();
        } else {
            user = _recoverAddressFromSignature(
                keccak256(
                    abi.encodePacked(
                        params.nftAddress,
                        params.tokenId,
                        params.payToken,
                        params.owner
                    )
                ),
                params.signature
            );
        }

        Listing memory listedItem = listings[params.nftAddress][params.tokenId][
            params.owner
        ];

        require(listedItem.payToken == params.payToken, "invalid pay token");

        if (listedItem.endingTime > 0) {
            require(
                listedItem.endingTime > _getNow(),
                "item ending time exceeded"
            );
        }

        uint256 price = listedItem.pricePerItem.mul(listedItem.quantity);
        uint256 feeAmount = price.mul(platformFee).div(1e3);

        IERC20(params.payToken).safeTransferFrom(
            user,
            feeReceipient,
            feeAmount
        );

        INiftyRoyaltyRegistry royaltyRegistry = INiftyRoyaltyRegistry(
            addressRegistry.royaltyRegistry()
        );

        address minter;
        uint256 royaltyAmount;

        (minter, royaltyAmount) = royaltyRegistry.royaltyInfo(
            params.nftAddress,
            params.tokenId,
            price
        );

        if (minter != address(0) && royaltyAmount != 0) {
            IERC20(params.payToken).safeTransferFrom(
                user,
                minter,
                royaltyAmount
            );
        }

        if (price.sub(feeAmount).sub(royaltyAmount) > 0) {
            IERC20(params.payToken).safeTransferFrom(
                user,
                params.owner,
                price.sub(feeAmount).sub(royaltyAmount)
            );
        }

        // Transfer NFT to buyer
        if (IERC165(params.nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721(params.nftAddress).safeTransferFrom(
                params.owner,
                user,
                params.tokenId
            );
        } else {
            IERC1155(params.nftAddress).safeTransferFrom(
                params.owner,
                user,
                params.tokenId,
                listedItem.quantity,
                bytes("")
            );
        }

        emit ItemSold(
            params.owner,
            user,
            params.nftAddress,
            params.tokenId,
            listedItem.quantity,
            params.payToken,
            getPrice(params.payToken),
            price.div(listedItem.quantity)
        );
        delete (listings[params.nftAddress][params.tokenId][params.owner]);
    }

    function _createOffer(CreateOfferParams memory params) internal {
        address user;

        if (params.signature.length == 0) {
            user = _msgSender();
        } else {
            user = _recoverAddressFromSignature(
                keccak256(
                    abi.encodePacked(
                        params.nftAddress,
                        params.tokenId,
                        params.payToken,
                        params.quantity,
                        params.pricePerItem,
                        params.deadline
                    )
                ),
                params.signature
            );
        }

        require(
            IERC165(params.nftAddress).supportsInterface(INTERFACE_ID_ERC721) ||
                IERC165(params.nftAddress).supportsInterface(
                    INTERFACE_ID_ERC1155
                ),
            "invalid nft address"
        );

        require(params.deadline > _getNow(), "invalid expiration");

        _validPayToken(address(params.payToken));

        require(
            IERC20(params.payToken).transferFrom(
                user,
                address(this),
                params.pricePerItem.mul(params.quantity)
            ),
            "insufficient balance or not approved"
        );

        Offer memory offer = offers[params.nftAddress][params.tokenId][user];

        if (offer.quantity > 0) {
            delete (offers[params.nftAddress][params.tokenId][user]);

            IERC20(offer.payToken).safeTransfer(
                user,
                offer.pricePerItem.mul(offer.quantity)
            );
        }

        offers[params.nftAddress][params.tokenId][user] = Offer(
            params.payToken,
            params.quantity,
            params.pricePerItem,
            params.deadline
        );

        emit OfferCreated(
            user,
            params.nftAddress,
            params.tokenId,
            params.quantity,
            address(params.payToken),
            params.pricePerItem,
            params.deadline
        );
    }

    function _cancelOffer(CancelOfferParams memory params) internal {
        address user;

        if (params.signature.length == 0) {
            user = _msgSender();
        } else {
            user = _recoverAddressFromSignature(
                keccak256(abi.encodePacked(params.nftAddress, params.tokenId)),
                params.signature
            );
        }

        Offer memory offer = offers[params.nftAddress][params.tokenId][
            _msgSender()
        ];

        delete (offers[params.nftAddress][params.tokenId][_msgSender()]);

        if (offer.quantity > 0) {
            IERC20(offer.payToken).safeTransfer(
                _msgSender(),
                offer.pricePerItem.mul(offer.quantity)
            );
        }

        emit OfferCanceled(user, params.nftAddress, params.tokenId);
    }

    function _acceptOffer(AcceptOfferParams memory params) internal {
        address user;

        if (params.signature.length == 0) {
            user = _msgSender();
        } else {
            user = _recoverAddressFromSignature(
                keccak256(
                    abi.encodePacked(
                        params.nftAddress,
                        params.tokenId,
                        params.creator
                    )
                ),
                params.signature
            );
        }

        Offer memory offer = offers[params.nftAddress][params.tokenId][
            params.creator
        ];

        _validOwner(params.nftAddress, params.tokenId, user, offer.quantity);

        uint256 price = offer.pricePerItem.mul(offer.quantity);
        uint256 feeAmount = price.mul(platformFee).div(1e3);

        delete (offers[params.nftAddress][params.tokenId][params.creator]);
        delete (listings[params.nftAddress][params.tokenId][user]);

        IERC20(offer.payToken).safeTransfer(feeReceipient, feeAmount);

        INiftyRoyaltyRegistry royaltyRegistry = INiftyRoyaltyRegistry(
            addressRegistry.royaltyRegistry()
        );

        address minter;
        uint256 royaltyAmount;

        (minter, royaltyAmount) = royaltyRegistry.royaltyInfo(
            params.nftAddress,
            params.tokenId,
            price
        );

        if (minter != address(0) && royaltyAmount != 0) {
            IERC20(offer.payToken).safeTransfer(minter, royaltyAmount);
        }

        if (price.sub(feeAmount).sub(royaltyAmount) > 0) {
            IERC20(offer.payToken).safeTransfer(
                _msgSender(),
                price.sub(feeAmount).sub(royaltyAmount)
            );
        }

        // Transfer NFT to buyer
        if (IERC165(params.nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721(params.nftAddress).safeTransferFrom(
                user,
                params.creator,
                params.tokenId
            );
        } else {
            IERC1155(params.nftAddress).safeTransferFrom(
                user,
                params.creator,
                params.tokenId,
                offer.quantity,
                bytes("")
            );
        }

        emit ItemSold(
            user,
            params.creator,
            params.nftAddress,
            params.tokenId,
            offer.quantity,
            address(offer.payToken),
            getPrice(address(offer.payToken)),
            offer.pricePerItem
        );
    }

    function _recoverAddressFromSignature(
        bytes32 _dataHash,
        bytes memory _signature
    ) public pure returns (address) {
        // add the prefix "\x19Ethereum Signed Message:\n32"
        bytes32 _prefixedHash = ECDSA.toEthSignedMessageHash(_dataHash);

        // recover the signer's address and return it
        return ECDSA.recover(_prefixedHash, _signature);
    }
}
