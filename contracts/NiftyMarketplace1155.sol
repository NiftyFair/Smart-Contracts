// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

interface INiftyAddressRegistry {
    function artion() external view returns (address);

    function bundleMarketplace() external view returns (address);

    function auction() external view returns (address);

    function factory() external view returns (address);

    function privateFactory() external view returns (address);

    function artFactory() external view returns (address);

    function privateArtFactory() external view returns (address);

    function tokenRegistry() external view returns (address);

    function priceFeed() external view returns (address);

    function royaltyRegistry() external view returns (address);
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

contract NiftyMarketplace1155 is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using AddressUpgradeable for address payable;
    using SafeERC20 for IERC20;

    /// @notice Events for the contract
    event ItemListed(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 tokenNftId,
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
        uint256 tokenNftId,
        uint256 quantity,
        address payToken,
        int256 unitPrice,
        uint256 pricePerItem
    );

    event ItemUpdated(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 tokenNftId,
        address payToken,
        uint256 newPrice
    );

    event ItemCanceled(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 tokenNftId
    );

    event OfferCreated(
        address indexed creator,
        address indexed nft,
        uint256 tokenId,
        uint256 tokenNftId,
        uint256 quantity,
        address payToken,
        uint256 pricePerItem,
        uint256 deadline
    );

    event OfferCanceled(
        address indexed creator,
        address indexed nft,
        uint256 tokenId,
        uint256 tokenNftId
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

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

    /// @notice NftAddress -> Token ID -> Owner -> Listing item
    mapping(bytes32 => Listing) public listings;

    /// @notice NftAddress -> Token ID -> Offerer -> Offer
    mapping(bytes32 => Offer) public offers;

    /// @notice Platform fee
    uint16 public platformFee;

    /// @notice Platform fee receipient
    address payable public feeReceipient;

    /// @notice Address registry
    INiftyAddressRegistry public addressRegistry;

    modifier isListed(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _tokenNftId,
        address _owner
    ) {
        require(
            listings[
                keccak256(
                    abi.encodePacked(_nftAddress, _tokenId, _tokenNftId, _owner)
                )
            ].quantity > 0,
            "not listed item"
        );
        _;
    }

    modifier notListed(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _tokenNftId,
        address _owner
    ) {
        require(
            listings[
                keccak256(
                    abi.encodePacked(_nftAddress, _tokenId, _tokenNftId, _owner)
                )
            ].quantity == 0,
            "already listed"
        );
        _;
    }

    modifier validListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _tokenNftId,
        address _owner
    ) {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155)) {
            require(
                IERC1155(_nftAddress).balanceOf(_owner, _tokenId) >= uint256(1)
            );
        } else {
            revert("invalid nft address");
        }

        require(
            block.timestamp >=
                listings[
                    keccak256(
                        abi.encodePacked(
                            _nftAddress,
                            _tokenId,
                            _tokenNftId,
                            _owner
                        )
                    )
                ].startingTime,
            "item not buyable"
        );
        _;
    }

    modifier offerExists(
        address _nftAddress,
        uint256 _tokenId,
        address _creator
    ) {
        bytes32 offerKey = keccak256(
            abi.encodePacked(_nftAddress, _tokenId, _creator)
        );

        require(
            offers[offerKey].quantity > 0 &&
                offers[offerKey].deadline > block.timestamp,
            "offer not exists or expired"
        );
        _;
    }

    /// @notice Contract initializer
    function initialize(address payable _feeRecipient, uint16 _platformFee)
        public
        initializer
    {
        platformFee = _platformFee;
        feeReceipient = _feeRecipient;

        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /// @notice Method for listing NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _tokenNftId TokenNftId
    /// @param _payToken Paying token
    /// @param _pricePerItem sale price for each iteam
    /// @param _startingTime scheduling for a future sale
    function listItem(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _tokenNftId,
        address _payToken,
        uint256 _pricePerItem,
        uint256 _startingTime,
        uint256 _endingTime
    ) external notListed(_nftAddress, _tokenId, _tokenNftId, _msgSender()) {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155)) {
            require(
                IERC1155(_nftAddress).balanceOf(_msgSender(), _tokenId) >=
                    uint256(1),
                "must hold enough nfts"
            );

            require(
                IERC1155(_nftAddress).isApprovedForAll(
                    _msgSender(),
                    address(this)
                ),
                "item not approved"
            );
        } else {
            revert("invalid nft address");
        }

        require(
            _payToken == address(0) ||
                (addressRegistry.tokenRegistry() != address(0) &&
                    INiftyTokenRegistry(addressRegistry.tokenRegistry())
                        .enabled(_payToken)),
            "invalid pay token"
        );

        listings[
            keccak256(
                abi.encodePacked(
                    _nftAddress,
                    _tokenId,
                    _tokenNftId,
                    _msgSender()
                )
            )
        ] = Listing(
            uint256(1),
            _payToken,
            _pricePerItem,
            _startingTime,
            _endingTime
        );

        emit ItemListed(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _tokenNftId,
            uint256(1),
            _payToken,
            _pricePerItem,
            _startingTime,
            _endingTime
        );
    }

    /// @notice Method for canceling listed NFT
    function cancelListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _tokenNftId
    )
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _tokenNftId, _msgSender())
    {
        _cancelListing(_nftAddress, _tokenId, _tokenNftId, _msgSender());
    }

    /// @notice Method for updating listed NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _tokenNftId TokenNftId
    /// @param _payToken payment token
    /// @param _newPrice New sale price for each iteam
    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _tokenNftId,
        address _payToken,
        uint256 _newPrice
    )
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _tokenNftId, _msgSender())
    {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155)) {
            require(
                IERC1155(_nftAddress).balanceOf(_msgSender(), _tokenId) >=
                    listings[
                        keccak256(
                            abi.encodePacked(
                                _nftAddress,
                                _tokenId,
                                _tokenNftId,
                                _msgSender()
                            )
                        )
                    ].quantity,
                "not owning item"
            );
        } else {
            revert("invalid nft address");
        }

        require(
            _payToken == address(0) ||
                (addressRegistry.tokenRegistry() != address(0) &&
                    INiftyTokenRegistry(addressRegistry.tokenRegistry())
                        .enabled(_payToken)),
            "invalid pay token"
        );

        bytes32 listingKey = keccak256(
            abi.encodePacked(_nftAddress, _tokenId, _tokenNftId, _msgSender())
        );

        listings[listingKey].payToken = _payToken;
        listings[listingKey].pricePerItem = _newPrice;

        emit ItemUpdated(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _tokenNftId,
            _payToken,
            _newPrice
        );
    }

    /// @notice Method for buying listed NFT
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _tokenNftId TokenNftId
    /// @param _owner current owner
    function buyItem(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _tokenNftId,
        address _payToken,
        address _owner
    )
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _tokenNftId, _owner)
        validListing(_nftAddress, _tokenId, _tokenNftId, _owner)
    {
        bytes32 listingKey = keccak256(
            abi.encodePacked(_nftAddress, _tokenId, _tokenNftId, _owner)
        );

        require(
            listings[listingKey].payToken == _payToken,
            "invalid pay token"
        );

        if (listings[listingKey].endingTime > 0) {
            require(
                listings[listingKey].endingTime > block.timestamp,
                "item ending time exceeded"
            );
        }

        _buyItem(_nftAddress, _tokenId, _tokenNftId, _payToken, _owner);
    }

    function _buyItem(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _tokenNftId,
        address _payToken,
        address _owner
    ) private {
        bytes32 listingKey = keccak256(
            abi.encodePacked(_nftAddress, _tokenId, _tokenNftId, _owner)
        );

        uint256 price = listings[listingKey].pricePerItem;

        IERC20(_payToken).safeTransferFrom(
            _msgSender(),
            feeReceipient,
            price.mul(platformFee).div(1e3)
        );

        INiftyRoyaltyRegistry royaltyRegistry = INiftyRoyaltyRegistry(
            addressRegistry.royaltyRegistry()
        );

        address minter;
        uint256 royaltyAmount;

        (minter, royaltyAmount) = royaltyRegistry.royaltyInfo(
            _nftAddress,
            _tokenId,
            price
        );

        if (minter != address(0) && royaltyAmount != 0) {
            IERC20(_payToken).safeTransferFrom(
                _msgSender(),
                minter,
                royaltyAmount
            );
        }

        if (price.sub(price.mul(platformFee).div(1e3)).sub(royaltyAmount) > 0) {
            IERC20(_payToken).safeTransferFrom(
                _msgSender(),
                _owner,
                price.sub(price.mul(platformFee).div(1e3)).sub(royaltyAmount)
            );
        }

        IERC1155(_nftAddress).safeTransferFrom(
            _owner,
            _msgSender(),
            _tokenId,
            uint256(1),
            bytes("")
        );

        delete (listings[listingKey]);

        emit ItemSold(
            _owner,
            _msgSender(),
            _nftAddress,
            _tokenId,
            _tokenNftId,
            uint256(1),
            _payToken,
            getPrice(_payToken),
            price
        );
    }

    /// @notice Method for offering item
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _payToken Paying toke
    /// @param _pricePerItem Price per item
    /// @param _deadline Offer expiration
    function createOffer(
        address _nftAddress,
        uint256 _tokenId,
        IERC20 _payToken,
        uint256 _pricePerItem,
        uint256 _deadline
    ) external nonReentrant {
        require(
            IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155),
            "invalid nft address"
        );

        require(_deadline > block.timestamp, "invalid expiration");

        require(
            address(_payToken) == address(0) ||
                (addressRegistry.tokenRegistry() != address(0) &&
                    INiftyTokenRegistry(addressRegistry.tokenRegistry())
                        .enabled(address(_payToken))),
            "invalid pay token"
        );

        require(
            IERC20(_payToken).transferFrom(
                _msgSender(),
                address(this),
                _pricePerItem
            ),
            "insufficient balance or not approved"
        );

        bytes32 offerKey = keccak256(
            abi.encodePacked(_nftAddress, _tokenId, _msgSender())
        );

        if (offers[offerKey].quantity > 0) {
            IERC20(offers[offerKey].payToken).safeTransfer(
                _msgSender(),
                offers[offerKey].pricePerItem
            );

            delete (offers[offerKey]);
        }

        offers[offerKey] = Offer(
            _payToken,
            uint256(1),
            _pricePerItem,
            _deadline
        );

        emit OfferCreated(
            _msgSender(),
            _nftAddress,
            _tokenId,
            uint256(0),
            uint256(1),
            address(_payToken),
            _pricePerItem,
            _deadline
        );
    }

    /// @notice Method for canceling the offer
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    function cancelOffer(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
    {
        bytes32 offerKey = keccak256(
            abi.encodePacked(_nftAddress, _tokenId, _msgSender())
        );

        if (offers[offerKey].quantity > 0) {
            IERC20(offers[offerKey].payToken).safeTransfer(
                _msgSender(),
                offers[offerKey].pricePerItem
            );

            delete (offers[offerKey]);
        }

        emit OfferCanceled(_msgSender(), _nftAddress, _tokenId, uint256(0));
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
        bytes32 offerKey = keccak256(
            abi.encodePacked(_nftAddress, _tokenId, _creator)
        );

        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155)) {
            require(
                IERC1155(_nftAddress).balanceOf(_msgSender(), _tokenId) >=
                    offers[offerKey].quantity,
                "not owning item"
            );
        } else {
            revert("invalid nft address");
        }

        uint256 price = offers[offerKey].pricePerItem;

        IERC20(offers[offerKey].payToken).safeTransfer(
            feeReceipient,
            price.mul(platformFee).div(1e3)
        );

        address minter;
        uint256 royaltyAmount;

        (minter, royaltyAmount) = INiftyRoyaltyRegistry(
            addressRegistry.royaltyRegistry()
        ).royaltyInfo(_nftAddress, _tokenId, price);

        if (minter != address(0) && royaltyAmount != 0) {
            IERC20(offers[offerKey].payToken).safeTransfer(
                minter,
                royaltyAmount
            );
        }

        if (price.sub(price.mul(platformFee).div(1e3)).sub(royaltyAmount) > 0) {
            IERC20(offers[offerKey].payToken).safeTransfer(
                _creator,
                price.sub(price.mul(platformFee).div(1e3)).sub(royaltyAmount)
            );
        }

        IERC1155(_nftAddress).safeTransferFrom(
            _msgSender(),
            _creator,
            _tokenId,
            uint256(1),
            bytes("")
        );

        emit ItemSold(
            _msgSender(),
            _creator,
            _nftAddress,
            _tokenId,
            uint256(0),
            uint256(1),
            address(offers[offerKey].payToken),
            getPrice(address(offers[offerKey].payToken)),
            offers[offerKey].pricePerItem
        );

        delete (offers[offerKey]);

        delete (listings[offerKey]);
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
            unitPrice = unitPrice * (int256(10)**(18 - decimals));
        } else {
            unitPrice = unitPrice / (int256(10)**(decimals - 18));
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
    function updatePlatformFeeRecipient(address payable _platformFeeRecipient)
        external
        onlyOwner
    {
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

    function _cancelListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _tokenNftId,
        address _owner
    ) private {
        bytes32 listingKey = keccak256(
            abi.encodePacked(_nftAddress, _tokenId, _tokenNftId, _owner)
        );

        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155)) {
            require(
                IERC1155(_nftAddress).balanceOf(_owner, _tokenId) >=
                    listings[listingKey].quantity,
                "not owning item"
            );
        } else {
            revert("invalid nft address");
        }

        delete (listings[listingKey]);

        emit ItemCanceled(_owner, _nftAddress, _tokenId, _tokenNftId);
    }
}
