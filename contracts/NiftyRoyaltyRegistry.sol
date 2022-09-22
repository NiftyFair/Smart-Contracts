// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./library/IERC2981Royalties.sol";
import "./library/IERC2981RoyaltySetter.sol";

interface IERC721C is IERC721 {
    function owner() external view returns (address);

    function creatorOf(uint256 _tokenId) external view returns (address);
}

contract NiftyRoyaltyRegistry is Ownable {
    /// @dev Events of the contract
    event RoyaltyUpdate(
        address collection,
        uint16 royalty,
        address reciever,
        address updatedBy
    );
    
    event RoyaltyTokenUpdate(
        address collection,
        uint256 tokenId,
        uint16 royalty,
        address receiver,
        address updatedBy
    );

    uint16 maxRoyalty = 1000;

    address public royaltyMigrationManager;

    struct RoyaltyInfo {
        address receiver;
        uint16 royaltyPercent;
    }

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    bytes4 private constant _INTERFACE_ID_ERC2981_SETTER = 0xb11d44f1;

    // Contract ownerships
    mapping(address => address) public ownershipOverrides;

    // NftAddress -> TokenId -> RoyaltyInfo
    mapping(address => mapping(uint256 => RoyaltyInfo)) internal _royalties;

    modifier auth(address _collection) {
        require(
            isOwner(_collection, _msgSender()),
            "not authorized"
        );
        _;
    }

    modifier authToken(address _collection, uint256 _tokenId) {
        require(
            isTokenOwner(_collection, _msgSender(), _tokenId),
            "not authorized"
        );
        _;
    }

    /**
     * @dev returns the owner of a collection
     */
    function isOwner(address _collection, address _collectionOwner)
        public
        view
        returns (bool)
    {
        return _collectionOwner == owner() || _collectionOwner == ownershipOverrides[_collection] || _collectionOwner == IERC721C(_collection).owner();
    }

    /**
     * @dev returns the owner of a collection
     */
    function isTokenOwner(address _collection, address _tokenOwner, uint256 _tokenId)
        public
        view
        returns (bool)
    {
        return _tokenOwner == owner() || _tokenOwner == IERC721C(_collection).creatorOf(_tokenId);
    }

    function ownershipOveride(address _contract) public view returns (address) {
        return ownershipOverrides[_contract];
    }

    function setRoyalty(
        address _collection,
        address _receiver,
        uint16 _royaltyPercent
    ) external auth(_collection) {
        if (
            IERC165(_collection).supportsInterface(_INTERFACE_ID_ERC2981_SETTER)
        ) {
            IERC2981RoyaltySetter(_collection).setRoyalty(
                _receiver,
                _royaltyPercent
            );

            emit RoyaltyUpdate(
                _collection,
                _royaltyPercent,
                _receiver,
                msg.sender
            );
            return;
        }

        _setTokenRoyalty(_collection, 0, _receiver, _royaltyPercent);
        emit RoyaltyUpdate(_collection, _royaltyPercent, _receiver, msg.sender);
    }

    function setTokenRoyalty(
        address _collection,
        uint256 _tokenId,
        address _receiver,
        uint16 _royaltyPercent
    ) external authToken(_collection, _tokenId) {
        if (
            IERC165(_collection).supportsInterface(_INTERFACE_ID_ERC2981_SETTER)
        ) {
            IERC2981RoyaltySetter(_collection).setTokenRoyalty(
                _tokenId,
                _receiver,
                _royaltyPercent
            );

            emit RoyaltyTokenUpdate(
                _collection,
                _tokenId,
                _royaltyPercent,
                _receiver,
                msg.sender
            );
            return;
        }

        _setTokenRoyalty(_collection, _tokenId, _receiver, _royaltyPercent);
        emit RoyaltyTokenUpdate(
            _collection,
            _tokenId,
            _royaltyPercent,
            _receiver,
            msg.sender
        );
    }

    function royaltyInfo(
        address _collection,
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (address _receiver, uint256 _royaltyAmount) {
        if (IERC165(_collection).supportsInterface(_INTERFACE_ID_ERC2981)) {
            (_receiver, _royaltyAmount) = IERC2981Royalties(_collection)
                .royaltyInfo(_tokenId, _salePrice);
        } else {
            (_receiver, _royaltyAmount) = _royaltyInfo(
                _collection,
                _tokenId,
                _salePrice
            );
        }
    }

    function _setTokenRoyalty(
        address _collection,
        uint256 _tokenId,
        address _receiver,
        uint16 _royaltyPercent
    ) internal {
        require(_royaltyPercent <= maxRoyalty, "Royalty too high");

        _royalties[_collection][_tokenId] = RoyaltyInfo(
            _receiver,
            _royaltyPercent
        );
    }

    function _royaltyInfo(
        address _collection,
        uint256 _tokenId,
        uint256 _salePrice
    ) internal view returns (address _receiver, uint256 _royaltyAmount) {
        RoyaltyInfo memory royalty = _royalties[_collection][_tokenId];

        if (royalty.receiver == address(0)) {
            royalty = _royalties[_collection][0]; // use collection-wide royalty
        }

        _receiver = royalty.receiver;
        _royaltyAmount = (_salePrice * royalty.royaltyPercent) / 10000;

        return (_receiver, _royaltyAmount);
    }

    /**
     @notice Update MigrationManager address
     @dev Only admin
     */
    function updateMaxRoyalty(uint16 _maxRoyalty) external onlyOwner {
        maxRoyalty = _maxRoyalty;
    }

    /**
     @notice Update MigrationManager address
     @dev Only admin
     */
    function updateMigrationManager(address _royaltyMigrationManager)
        external
        onlyOwner
    {
        royaltyMigrationManager = _royaltyMigrationManager;
    }

    /**
     @notice Update MigrationManager address
     @dev Only admin
     */
    function updateOwnershipOverrides(address _contract, address _contractOwner)
        external
        onlyOwner
    {
        ownershipOverrides[_contract] = _contractOwner;
    }
}
