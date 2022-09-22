// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../NiftyAuction.sol";

contract BiddingContractMock {
    NiftyAuction public auctionContract;

    constructor(NiftyAuction _auctionContract) public {
        auctionContract = _auctionContract;
    }

    /* function bid(address _nftAddress, uint256 _tokenId) external payable {
        auctionContract.placeBid{value: msg.value}(_nftAddress, _tokenId);
    } */
}
