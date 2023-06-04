// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

interface INiftyAddressRegistry {
    function marketplace() external view returns (address);

    function tokenRegistry() external view returns (address);

    function royaltyRegistry() external view returns (address);
}

interface INiftyMarketplace {
    function getPrice(address) external view returns (int256);
}

interface INiftyTokenRegistry {
    function enabled(address) external returns (bool);
}

interface INiftyRoyaltyRegistry {
    function royaltyInfo(
        address _collection,
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (address, uint256);
}

/**
 * @notice Secondary sale auction contract for NFTs
 */
contract NiftyAuction is
    ERC721Holder,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using AddressUpgradeable for address payable;
    using SafeERC20 for IERC20;

    /// @notice Event emitted only on construction. To be used by indexers
    event NiftyFairAuctionContractDeployed();

    event PauseToggled(bool isPaused);

    event AuctionCreated(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address payToken
    );

    event UpdateAuctionReservePrice(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address payToken,
        uint256 reservePrice
    );

    event UpdatePlatformFee(uint256 platformFee);

    event UpdatePlatformFeeRecipient(address payable platformFeeRecipient);

    event UpdateMinBidIncrement(uint256 minBidIncrement);

    event UpdateBidWithdrawalLockTime(uint256 bidWithdrawalLockTime);

    event BidPlaced(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 bid
    );

    event BidWithdrawn(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 bid
    );

    event BidRefunded(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 bid
    );

    event AuctionResulted(
        address oldOwner,
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed winner,
        address payToken,
        int256 unitPrice,
        uint256 winningBid
    );

    event AuctionCancelled(address indexed nftAddress, uint256 indexed tokenId);

    /// @notice Parameters of an auction
    struct Auction {
        address owner;
        address payToken;
        uint256 minBid;
        uint256 reservePrice;
        uint256 startTime;
        uint256 endTime;
        bool resulted;
    }

    /// @notice Information about the sender that placed a bit on an auction
    struct HighestBid {
        address payable bidder;
        uint256 bid;
        uint256 lastBidTime;
    }

    struct CreatAuctionParams {
        address user;
        address nftAddress;
        uint256 tokenId;
        address payToken;
        uint256 reservePrice;
        uint256 startTimestamp;
        bool minBidReserve;
        uint256 endTimestamp;
    }

    struct PlaceBidParams {
        address user;
        address nftAddress;
        uint256 tokenId;
        uint256 bidAmount;
    }

    struct ResultAuctionParams {
        address user;
        address nftAddress;
        uint256 tokenId;
        address winner;
        uint256 winningBid;
    }

    struct CancelAuctionParams {
        address user;
        address nftAddress;
        uint256 tokenId;
        address owner;
    }

    /// @notice ERC721 Address -> Token ID -> Auction Parameters
    mapping(address => mapping(uint256 => Auction)) public auctions;

    /// @notice ERC721 Address -> Token ID -> highest bidder info (if a bid has been received)
    mapping(address => mapping(uint256 => HighestBid)) public highestBids;

    /// @notice globally and across all auctions, the amount by which a bid has to increase
    uint256 public minBidIncrement = 1;

    /// @notice global bid withdrawal lock time
    uint256 public bidWithdrawalLockTime = 20 minutes;

    /// @notice global platform fee, assumed to always be to 1 decimal place i.e. 25 = 2.5%
    uint256 public platformFee = 25;

    /// @notice Used to track and set the maximum allowed auction time (6 months = 6 x 31 days)
    uint256 public constant maxAuctionLength = 186 days;

    /// @notice where to send platform fee funds to
    address payable public platformFeeRecipient;

    /// @notice Address registry
    INiftyAddressRegistry public addressRegistry;

    /// @notice for switching off auction creations, bids and withdrawals
    bool public isPaused;

    function whenNotPaused() public view returns (bool) {
        return !isPaused;
    }

    function onlyNotContract() public view returns (bool) {
        return _msgSender() == tx.origin;
    }

    /// @notice Contract initializer
    function initialize(
        address payable _platformFeeRecipient
    ) public initializer {
        require(
            _platformFeeRecipient != address(0),
            "NiftyAuction: Invalid Platform Fee Recipient"
        );

        platformFeeRecipient = _platformFeeRecipient;
        emit NiftyFairAuctionContractDeployed();

        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
     @notice Creates a new auction for a given item
     @dev Only the owner of item can create an auction and must have approved the contract
     @dev In addition to owning the item, the sender also has to have the MINTER role.
     @dev End time for the auction must be in the future.
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _payToken Paying token
     @param _reservePrice Item cannot be sold for less than this or minBidIncrement, whichever is higher
     @param _startTimestamp Unix epoch in seconds for the auction start time
     @param _endTimestamp Unix epoch in seconds for the auction end time.
     */
    function createAuction(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        uint256 _reservePrice,
        uint256 _startTimestamp,
        bool minBidReserve,
        uint256 _endTimestamp
    ) external nonReentrant {
        require(whenNotPaused(), "contract paused");
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == _msgSender() &&
                IERC721(_nftAddress).isApprovedForAll(
                    _msgSender(),
                    address(this)
                ),
            "not owner and or contract not approved"
        );

        require(
            (addressRegistry.tokenRegistry() != address(0) &&
                INiftyTokenRegistry(addressRegistry.tokenRegistry()).enabled(
                    _payToken
                )),
            "invalid pay token"
        );

        // Adds hard limits to cap the maximum auction length
        require(
            _endTimestamp <= (_getNow() + maxAuctionLength),
            "Auction time exceeds maximum length"
        );

        CreatAuctionParams memory params = CreatAuctionParams({
            user: _msgSender(),
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            payToken: _payToken,
            reservePrice: _reservePrice,
            startTimestamp: _startTimestamp,
            minBidReserve: minBidReserve,
            endTimestamp: _endTimestamp
        });

        _createAuction(params);
    }

    /**
     @notice Creates a new auction for a given item
     @dev Only the owner of item can create an auction and must have approved the contract
     @dev In addition to owning the item, the sender also has to have the MINTER role.
     @dev End time for the auction must be in the future.
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _payToken Paying token
     @param _reservePrice Item cannot be sold for less than this or minBidIncrement, whichever is higher
     @param _startTimestamp Unix epoch in seconds for the auction start time
     @param _endTimestamp Unix epoch in seconds for the auction end time.
     @param _signature Signature of the auction params
     */
    function createAuctionMeta(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        uint256 _reservePrice,
        uint256 _startTimestamp,
        bool minBidReserve,
        uint256 _endTimestamp,
        bytes memory _signature
    ) external nonReentrant {
        address user = _recoverAddressFromSignature(
            keccak256(
                abi.encodePacked(
                    _nftAddress,
                    _tokenId,
                    _payToken,
                    _reservePrice,
                    _startTimestamp,
                    minBidReserve,
                    _endTimestamp
                )
            ),
            _signature
        );

        require(whenNotPaused(), "contract paused");
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == user &&
                IERC721(_nftAddress).isApprovedForAll(user, address(this)),
            "not owner and or contract not approved"
        );

        require(
            (addressRegistry.tokenRegistry() != address(0) &&
                INiftyTokenRegistry(addressRegistry.tokenRegistry()).enabled(
                    _payToken
                )),
            "invalid pay token"
        );

        // Adds hard limits to cap the maximum auction length
        require(
            _endTimestamp <= (_getNow() + maxAuctionLength),
            "Auction time exceeds maximum length"
        );

        CreatAuctionParams memory params = CreatAuctionParams({
            user: user,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            payToken: _payToken,
            reservePrice: _reservePrice,
            startTimestamp: _startTimestamp,
            minBidReserve: minBidReserve,
            endTimestamp: _endTimestamp
        });

        _createAuction(params);
    }

    /**
     @notice Places a new bid, out bidding the existing bidder if found and criteria is reached
     @dev Only callable when the auction is open
     @dev Bids from smart contracts are prohibited to prevent griefing with always reverting receiver
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _bidAmount Bid amount
     */
    function placeBid(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _bidAmount
    ) external nonReentrant {
        Auction memory auction = auctions[_nftAddress][_tokenId];

        require(whenNotPaused(), "contract paused");
        require(onlyNotContract(), "no contracts permitted");

        require(auction.endTime > 0, "No auction exists");

        // Ensure auction is in flight
        require(
            _getNow() >= auction.startTime,
            "bidding before auction started"
        );

        require(_getNow() <= auction.endTime, "bidding outside auction window");

        require(
            auction.payToken != address(0),
            "ERC20 method used for NF auction"
        );

        PlaceBidParams memory params = PlaceBidParams({
            user: _msgSender(),
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            bidAmount: _bidAmount
        });

        _placeBid(params);
    }

    /**
     @notice Places a new bid, out bidding the existing bidder if found and criteria is reached
     @dev Only callable when the auction is open
     @dev Bids from smart contracts are prohibited to prevent griefing with always reverting receiver
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _bidAmount Bid amount
     @param _signature Signature of the auction params
     */
    function placeBidMeta(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _bidAmount,
        bytes memory _signature
    ) external nonReentrant {
        address user = _recoverAddressFromSignature(
            keccak256(abi.encodePacked(_nftAddress, _tokenId, _bidAmount)),
            _signature
        );
        Auction memory auction = auctions[_nftAddress][_tokenId];

        require(whenNotPaused(), "contract paused");
        require(onlyNotContract(), "no contracts permitted");

        require(auction.endTime > 0, "No auction exists");

        // Ensure auction is in flight
        require(
            _getNow() >= auction.startTime,
            "bidding before auction started"
        );

        require(_getNow() <= auction.endTime, "bidding outside auction window");

        require(
            auction.payToken != address(0),
            "ERC20 method used for NF auction"
        );

        PlaceBidParams memory params = PlaceBidParams({
            user: user,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            bidAmount: _bidAmount
        });

        _placeBid(params);
    }

    /**
     @notice Allows the hightest bidder to withdraw the bid (after 12 hours post auction's end) 
     @dev Only callable by the existing top bidder
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     */
    function withdrawBid(
        address _nftAddress,
        uint256 _tokenId
    ) external nonReentrant {
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        Auction memory auction = auctions[_nftAddress][_tokenId];

        uint256 previousBid = highestBid.bid;

        require(whenNotPaused(), "contract paused");
        // Ensure highest bidder is the caller
        require(
            highestBid.bidder == _msgSender(),
            "you are not the highest bidder"
        );

        require(
            _getNow() > auction.endTime + 43200 ||
                (_getNow() > auction.endTime &&
                    highestBid.bid < auction.reservePrice),
            "can withdraw only after 12 hours (after auction ended)"
        );

        // Clean up the existing top bid
        delete highestBids[_nftAddress][_tokenId];

        // Refund the top bidder
        _refundHighestBidder(
            _nftAddress,
            _tokenId,
            payable(_msgSender()),
            previousBid
        );

        emit BidWithdrawn(_nftAddress, _tokenId, _msgSender(), previousBid);
    }

    /**
     @notice Allows the hightest bidder to withdraw the bid (after 12 hours post auction's end) 
     @dev Only callable by the existing top bidder
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _signature Signature of the auction params
     */
    function withdrawBidMeta(
        address _nftAddress,
        uint256 _tokenId,
        bytes memory _signature
    ) external nonReentrant {
        address user = _recoverAddressFromSignature(
            keccak256(abi.encodePacked(_nftAddress, _tokenId)),
            _signature
        );

        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        Auction memory auction = auctions[_nftAddress][_tokenId];

        uint256 previousBid = highestBid.bid;

        require(whenNotPaused(), "contract paused");
        // Ensure highest bidder is the caller
        require(highestBid.bidder == user, "you are not the highest bidder");

        require(
            _getNow() > auction.endTime + 43200 ||
                (_getNow() > auction.endTime &&
                    highestBid.bid < auction.reservePrice),
            "can withdraw only after 12 hours (after auction ended)"
        );

        // Clean up the existing top bid
        delete highestBids[_nftAddress][_tokenId];

        // Refund the top bidder
        _refundHighestBidder(_nftAddress, _tokenId, payable(user), previousBid);

        emit BidWithdrawn(_nftAddress, _tokenId, user, previousBid);
    }

    //////////
    // Admin /
    //////////

    /**
     @notice Closes a finished auction and rewards the highest bidder
     @dev Only admin or smart contract
     @dev Auction can only be resulted if there has been a bidder and reserve met.
     @dev If there have been no bids, the auction needs to be cancelled instead using `cancelAuction()`
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     */
    function resultAuction(
        address _nftAddress,
        uint256 _tokenId
    ) external nonReentrant {
        // Check the auction to see if it can be resulted
        Auction storage auction = auctions[_nftAddress][_tokenId];

        // Store auction owner
        address seller = auction.owner;

        // Get info on who the highest bidder is
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        address _winner = highestBid.bidder;
        uint256 _winningBid = highestBid.bid;

        // Ensure _msgSender() is either auction winner or seller
        require(
            _msgSender() == _winner || _msgSender() == seller,
            "_msgSender() must be auction winner or seller"
        );

        // Ensure this contract is the owner of the item
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == address(this),
            "address(this) must be the item owner"
        );

        // Check the auction real
        require(auction.endTime > 0, "no auction exists");

        // Check the auction has ended
        require(_getNow() > auction.endTime, "auction not ended");

        // Ensure auction not already resulted
        require(!auction.resulted, "auction already resulted");

        // Ensure there is a winner
        require(_winner != address(0), "no open bids");

        require(
            _winningBid >= auction.reservePrice || _msgSender() == seller,
            "highest bid is below reservePrice"
        );

        ResultAuctionParams memory params = ResultAuctionParams({
            user: _msgSender(),
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            winner: _winner,
            winningBid: _winningBid
        });

        _resultAuction(params);
    }

    /**
     @notice Closes a finished auction and rewards the highest bidder
     @dev Only admin or smart contract
     @dev Auction can only be resulted if there has been a bidder and reserve met.
     @dev If there have been no bids, the auction needs to be cancelled instead using `cancelAuction()`
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     */
    function resultAuctionMeta(
        address _nftAddress,
        uint256 _tokenId,
        bytes memory _signature
    ) external nonReentrant {
        address user = _recoverAddressFromSignature(
            keccak256(abi.encodePacked(_nftAddress, _tokenId)),
            _signature
        );
        // Check the auction to see if it can be resulted
        Auction storage auction = auctions[_nftAddress][_tokenId];

        // Store auction owner
        address seller = auction.owner;

        // Get info on who the highest bidder is
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        address _winner = highestBid.bidder;
        uint256 _winningBid = highestBid.bid;

        // Ensure user is either auction winner or seller
        require(
            user == _winner || user == seller,
            "user must be auction winner or seller"
        );

        // Ensure this contract is the owner of the item
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == address(this),
            "address(this) must be the item owner"
        );

        // Check the auction real
        require(auction.endTime > 0, "no auction exists");

        // Check the auction has ended
        require(_getNow() > auction.endTime, "auction not ended");

        // Ensure auction not already resulted
        require(!auction.resulted, "auction already resulted");

        // Ensure there is a winner
        require(_winner != address(0), "no open bids");

        require(
            _winningBid >= auction.reservePrice || user == seller,
            "highest bid is below reservePrice"
        );

        ResultAuctionParams memory params = ResultAuctionParams({
            user: user,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            winner: _winner,
            winningBid: _winningBid
        });

        _resultAuction(params);
    }

    /**
     @notice Results an auction that failed to meet the auction.reservePrice
     @dev Only admin or smart contract
     @dev Auction can only be fail-resulted if the auction has expired and the auction.reservePrice has not been met
     @dev If there have been no bids, the auction needs to be cancelled instead using `cancelAuction()`
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     */
    function resultFailedAuction(
        address _nftAddress,
        uint256 _tokenId
    ) external nonReentrant {
        // Check the auction to see if it can be resulted
        Auction storage auction = auctions[_nftAddress][_tokenId];

        // Store auction owner
        address seller = auction.owner;

        // Get info on who the highest bidder is
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        address payable topBidder = highestBid.bidder;
        uint256 topBid = highestBid.bid;

        // Ensure this contract is the owner of the item
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == address(this),
            "address(this) must be the item owner"
        );

        // Check if the auction exists
        require(auction.endTime > 0, "no auction exists");

        // Check if the auction has ended
        require(_getNow() > auction.endTime, "auction not ended");

        // Ensure auction not already resulted
        require(!auction.resulted, "auction already resulted");

        // Ensure _msgSender() is either auction topBidder or seller
        require(
            _msgSender() == topBidder || _msgSender() == seller,
            "_msgSender() must be auction topBidder or seller"
        );

        // Ensure the topBid is less than the auction.reservePrice
        require(topBidder != address(0), "no open bids");
        require(
            topBid < auction.reservePrice,
            "highest bid is >= reservePrice"
        );

        CancelAuctionParams memory params = CancelAuctionParams({
            user: _msgSender(),
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            owner: seller
        });

        _cancelAuction(params);
    }

    /**
     @notice Results an auction that failed to meet the auction.reservePrice
     @dev Only admin or smart contract
     @dev Auction can only be fail-resulted if the auction has expired and the auction.reservePrice has not been met
     @dev If there have been no bids, the auction needs to be cancelled instead using `cancelAuction()`
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _signature Signature of the auction params
     */
    function resultFailedAuctionMeta(
        address _nftAddress,
        uint256 _tokenId,
        bytes memory _signature
    ) external nonReentrant {
        address user = _recoverAddressFromSignature(
            keccak256(abi.encodePacked(_nftAddress, _tokenId)),
            _signature
        );
        // Check the auction to see if it can be resulted
        Auction storage auction = auctions[_nftAddress][_tokenId];

        // Store auction owner
        address seller = auction.owner;

        // Get info on who the highest bidder is
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        address payable topBidder = highestBid.bidder;
        uint256 topBid = highestBid.bid;

        // Ensure this contract is the owner of the item
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == address(this),
            "address(this) must be the item owner"
        );

        // Check if the auction exists
        require(auction.endTime > 0, "no auction exists");

        // Check if the auction has ended
        require(_getNow() > auction.endTime, "auction not ended");

        // Ensure auction not already resulted
        require(!auction.resulted, "auction already resulted");

        // Ensure user is either auction topBidder or seller
        require(
            user == topBidder || user == seller,
            "_msgSender() must be auction topBidder or seller"
        );

        // Ensure the topBid is less than the auction.reservePrice
        require(topBidder != address(0), "no open bids");
        require(
            topBid < auction.reservePrice,
            "highest bid is >= reservePrice"
        );

        CancelAuctionParams memory params = CancelAuctionParams({
            user: user,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            owner: seller
        });

        _cancelAuction(params);
    }

    /**
     @notice Cancels and inflight and un-resulted auctions, returning the funds to the top bidder if found
     @dev Only item owner
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     */
    function cancelAuction(
        address _nftAddress,
        uint256 _tokenId
    ) external nonReentrant {
        // Check valid and not resulted
        Auction memory auction = auctions[_nftAddress][_tokenId];
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];

        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == address(this) &&
                _msgSender() == auction.owner,
            "sender must be owner"
        );

        // Check auction is real
        require(auction.endTime > 0, "no auction exists");

        // Check auction not already resulted
        require(!auction.resulted, "auction already resulted");

        require(
            highestBid.bid < auction.reservePrice,
            "Highest bid is currently above reserve price"
        );

        CancelAuctionParams memory params = CancelAuctionParams({
            user: _msgSender(),
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            owner: _msgSender()
        });

        _cancelAuction(params);
    }

    /**
     @notice Cancels and inflight and un-resulted auctions, returning the funds to the top bidder if found
     @dev Only item owner
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     */
    function cancelAuctionMeta(
        address _nftAddress,
        uint256 _tokenId,
        bytes memory _signature
    ) external nonReentrant {
        address user = _recoverAddressFromSignature(
            keccak256(abi.encodePacked(_nftAddress, _tokenId)),
            _signature
        );

        // Check valid and not resulted
        Auction memory auction = auctions[_nftAddress][_tokenId];
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];

        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == address(this) &&
                user == auction.owner,
            "sender must be owner"
        );

        // Check auction is real
        require(auction.endTime > 0, "no auction exists");

        // Check auction not already resulted
        require(!auction.resulted, "auction already resulted");

        require(
            highestBid.bid < auction.reservePrice,
            "Highest bid is currently above reserve price"
        );

        CancelAuctionParams memory params = CancelAuctionParams({
            user: user,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            owner: user
        });

        _cancelAuction(params);
    }

    /**
     @notice Toggling the pause flag
     @dev Only admin
     */
    function toggleIsPaused() external onlyOwner {
        isPaused = !isPaused;
        emit PauseToggled(isPaused);
    }

    /**
     @notice Update the amount by which bids have to increase, across all auctions
     @dev Only admin
     @param _minBidIncrement New bid step in WEI
     */
    function updateMinBidIncrement(
        uint256 _minBidIncrement
    ) external onlyOwner {
        minBidIncrement = _minBidIncrement;
        emit UpdateMinBidIncrement(_minBidIncrement);
    }

    /**
     @notice Update the global bid withdrawal lockout time
     @dev Only admin
     @param _bidWithdrawalLockTime New bid withdrawal lock time
     */
    function updateBidWithdrawalLockTime(
        uint256 _bidWithdrawalLockTime
    ) external onlyOwner {
        bidWithdrawalLockTime = _bidWithdrawalLockTime;
        emit UpdateBidWithdrawalLockTime(_bidWithdrawalLockTime);
    }

    /**
     @notice Update the current reserve price for an auction
     @dev Only admin
     @dev Auction must exist
     @dev Reserve price can only be decreased and never increased
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     @param _reservePrice New Ether reserve price (WEI value)
     */
    function updateAuctionReservePrice(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external {
        Auction storage auction = auctions[_nftAddress][_tokenId];
        // Store the current reservePrice
        uint256 currentReserve = auction.reservePrice;

        // Ensures the sender owns the auction and the item is currently in escrow
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == address(this) &&
                _msgSender() == auction.owner,
            "Sender must be item owner and NFT must be in escrow"
        );

        // Ensures the auction hasn't been resulted
        require(!auction.resulted, "Auction already resulted");

        // Ensures auction exists
        require(auction.endTime > 0, "No auction exists");

        // Ensures the reserve price can only be decreased and never increased
        require(
            _reservePrice < currentReserve,
            "Reserve price can only be decreased"
        );

        auction.reservePrice = _reservePrice;

        if (auction.minBid == currentReserve) {
            auction.minBid = _reservePrice;
        }

        emit UpdateAuctionReservePrice(
            _nftAddress,
            _tokenId,
            auction.payToken,
            _reservePrice
        );
    }

    /**
     @notice Update the current reserve price for an auction
     @dev Only admin
     @dev Auction must exist
     @dev Reserve price can only be decreased and never increased
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     @param _reservePrice New Ether reserve price (WEI value)
     */
    function updateAuctionReservePriceMeta(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _reservePrice,
        bytes memory _signature
    ) external {
        address user = _recoverAddressFromSignature(
            keccak256(abi.encodePacked(_nftAddress, _tokenId, _reservePrice)),
            _signature
        );

        Auction storage auction = auctions[_nftAddress][_tokenId];
        // Store the current reservePrice
        uint256 currentReserve = auction.reservePrice;

        // Ensures the sender owns the auction and the item is currently in escrow
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == address(this) &&
                user == auction.owner,
            "Sender must be item owner and NFT must be in escrow"
        );

        // Ensures the auction hasn't been resulted
        require(!auction.resulted, "Auction already resulted");

        // Ensures auction exists
        require(auction.endTime > 0, "No auction exists");

        // Ensures the reserve price can only be decreased and never increased
        require(
            _reservePrice < currentReserve,
            "Reserve price can only be decreased"
        );

        auction.reservePrice = _reservePrice;

        if (auction.minBid == currentReserve) {
            auction.minBid = _reservePrice;
        }

        emit UpdateAuctionReservePrice(
            _nftAddress,
            _tokenId,
            auction.payToken,
            _reservePrice
        );
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
     @param _platformFeeRecipient payable address the address to sends the funds to
     */
    function updatePlatformFeeRecipient(
        address payable _platformFeeRecipient
    ) external onlyOwner {
        require(_platformFeeRecipient != address(0), "zero address");

        platformFeeRecipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }

    /**
     @notice Update NiftyAddressRegistry contract
     @dev Only admin
     */
    function updateAddressRegistry(address _registry) external onlyOwner {
        addressRegistry = INiftyAddressRegistry(_registry);
    }

    ///////////////
    // Accessors //
    ///////////////

    /**
     @notice Method for getting all info about the auction
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     */
    function getAuction(
        address _nftAddress,
        uint256 _tokenId
    )
        external
        view
        returns (
            address _owner,
            address _payToken,
            uint256 _reservePrice,
            uint256 _startTime,
            uint256 _endTime,
            bool _resulted,
            uint256 minBid
        )
    {
        Auction storage auction = auctions[_nftAddress][_tokenId];
        return (
            auction.owner,
            auction.payToken,
            auction.reservePrice,
            auction.startTime,
            auction.endTime,
            auction.resulted,
            auction.minBid
        );
    }

    /**
     @notice Method for getting all info about the highest bidder
     @param _tokenId Token ID of the NFT being auctioned
     */
    function getHighestBidder(
        address _nftAddress,
        uint256 _tokenId
    )
        external
        view
        returns (address payable _bidder, uint256 _bid, uint256 _lastBidTime)
    {
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        return (highestBid.bidder, highestBid.bid, highestBid.lastBidTime);
    }

    /////////////////////////
    // Internal and Private /
    /////////////////////////

    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _createAuction(CreatAuctionParams memory params) internal {
        // Ensure a token cannot be re-listed if previously successfully sold
        require(
            auctions[params.nftAddress][params.tokenId].endTime == 0,
            "auction already started"
        );

        // Check end time not before start time and that end is in the future
        require(
            params.endTimestamp > params.startTimestamp,
            "end time must be greater than start time"
        );

        // Check if start time not smaller than today
        require(
            params.startTimestamp > (_getNow() - 1 days),
            "invalid start time"
        );

        uint256 minimumBid = 0;

        if (params.minBidReserve) {
            minimumBid = params.reservePrice;
        }

        IERC721(params.nftAddress).safeTransferFrom(
            IERC721(params.nftAddress).ownerOf(params.tokenId),
            address(this),
            params.tokenId
        );

        // Setup the auction
        auctions[params.nftAddress][params.tokenId] = Auction({
            owner: params.user,
            payToken: params.payToken,
            minBid: minimumBid,
            reservePrice: params.reservePrice,
            startTime: params.startTimestamp,
            endTime: params.endTimestamp,
            resulted: false
        });

        emit AuctionCreated(params.nftAddress, params.tokenId, params.payToken);
    }

    function _placeBid(PlaceBidParams memory params) internal {
        Auction storage auction = auctions[params.nftAddress][params.tokenId];

        HighestBid storage highestBid = highestBids[params.nftAddress][
            params.tokenId
        ];
        uint256 minBidRequired = highestBid.bid.add(minBidIncrement);

        IERC20 payToken = IERC20(auction.payToken);

        require(whenNotPaused(), "contract paused");

        require(
            params.bidAmount >= minBidRequired,
            "failed to outbid highest bidder"
        );

        require(
            payToken.transferFrom(params.user, address(this), params.bidAmount),
            "insufficient balance or not approved"
        );

        if (auction.minBid == auction.reservePrice) {
            require(
                params.bidAmount >= auction.reservePrice,
                "bid cannot be lower than reserve price"
            );
        }

        if (highestBid.bidder != address(0)) {
            _refundHighestBidder(
                params.nftAddress,
                params.tokenId,
                highestBid.bidder,
                highestBid.bid
            );
        }

        // assign top bidder and bid time
        highestBid.bidder = payable(params.user);
        highestBid.bid = params.bidAmount;
        highestBid.lastBidTime = _getNow();

        emit BidPlaced(
            params.nftAddress,
            params.tokenId,
            params.user,
            params.bidAmount
        );
    }

    function _resultAuction(ResultAuctionParams memory params) internal {
        // Check the auction to see if it can be resulted
        Auction storage auction = auctions[params.nftAddress][params.tokenId];

        // Result the auction
        auction.resulted = true;

        // Clean up the highest bid
        delete highestBids[params.nftAddress][params.tokenId];

        uint256 payAmount;
        uint256 platformFeeBid = params.winningBid.mul(platformFee).div(1000);

        IERC20(auction.payToken).safeTransfer(
            platformFeeRecipient,
            platformFeeBid
        );

        payAmount = params.winningBid.sub(platformFeeBid);

        INiftyRoyaltyRegistry royaltyRegistry = INiftyRoyaltyRegistry(
            addressRegistry.royaltyRegistry()
        );

        address minter;
        uint256 royaltyAmount;

        (minter, royaltyAmount) = royaltyRegistry.royaltyInfo(
            params.nftAddress,
            params.tokenId,
            params.winningBid
        );

        if (minter != address(0) && royaltyAmount != 0) {
            IERC20 payToken = IERC20(auction.payToken);
            payToken.safeTransfer(minter, royaltyAmount);

            payAmount = payAmount.sub(royaltyAmount);
        }

        if (payAmount > 0) {
            IERC20 payToken = IERC20(auction.payToken);
            payToken.safeTransfer(auction.owner, payAmount);
        }

        // Transfer the token to the winner
        IERC721(params.nftAddress).safeTransferFrom(
            IERC721(params.nftAddress).ownerOf(params.tokenId),
            params.winner,
            params.tokenId
        );

        int256 price = INiftyMarketplace(addressRegistry.marketplace())
            .getPrice(auction.payToken);

        emit AuctionResulted(
            params.user,
            params.nftAddress,
            params.tokenId,
            params.winner,
            auction.payToken,
            price,
            params.winningBid
        );

        // Remove auction
        delete auctions[params.nftAddress][params.tokenId];
    }

    function _cancelAuction(CancelAuctionParams memory params) internal {
        // refund existing top bidder if found
        HighestBid memory highestBid = highestBids[params.nftAddress][
            params.tokenId
        ];
        if (highestBid.bidder != address(0)) {
            _refundHighestBidder(
                params.nftAddress,
                params.tokenId,
                highestBid.bidder,
                highestBid.bid
            );

            // Clear up highest bid
            delete highestBids[params.nftAddress][params.tokenId];
        }

        // Remove auction and top bidder
        delete auctions[params.nftAddress][params.tokenId];

        // Transfer the NFT ownership back to _msgSender()
        IERC721(params.nftAddress).safeTransferFrom(
            IERC721(params.nftAddress).ownerOf(params.tokenId),
            params.owner,
            params.tokenId
        );

        emit AuctionCancelled(params.nftAddress, params.tokenId);
    }

    /**
     @notice Used for sending back escrowed funds from a previous bid
     @param _currentHighestBidder Address of the last highest bidder
     @param _currentHighestBid Ether or Mona amount in WEI that the bidder sent when placing their bid
     */
    function _refundHighestBidder(
        address _nftAddress,
        uint256 _tokenId,
        address payable _currentHighestBidder,
        uint256 _currentHighestBid
    ) private {
        Auction memory auction = auctions[_nftAddress][_tokenId];

        IERC20 payToken = IERC20(auction.payToken);
        payToken.safeTransfer(_currentHighestBidder, _currentHighestBid);

        emit BidRefunded(
            _nftAddress,
            _tokenId,
            _currentHighestBidder,
            _currentHighestBid
        );
    }

    /**
     * @notice Reclaims ERC20 Compatible tokens for entire balance
     * @dev Only access controls admin
     * @param _tokenContract The address of the token contract
     */
    function reclaimERC20(address _tokenContract) external onlyOwner {
        require(_tokenContract != address(0), "Invalid address");
        IERC20 token = IERC20(_tokenContract);
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(_msgSender(), balance);
    }

    function _recoverAddressFromSignature(
        bytes32 _dataHash,
        bytes memory _signature
    ) public pure returns (address) {
        bytes32 _prefixedHash = ECDSA.toEthSignedMessageHash(_dataHash);
        address recoveredAddress = ECDSA.recover(_prefixedHash, _signature);

        require(recoveredAddress != address(0), "Invalid signature");

        return recoveredAddress;
    }
}
