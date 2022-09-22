// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IERC2981RoyaltySetter is IERC165 {
    // bytes4(keccak256('setRoyalty(address,uint16)')) == 0xc9c628a2
    // bytes4(keccak256('setTokenRoyalty(uint256,address,uint16)')) == 0x78db6c53
    // => Interface ID = 0xc9c628a2 ^ 0x78db6c53 == 0xb11d44f1

    // Set collection-wide default royalty.
    function setRoyalty(address _receiver, uint16 _royaltyPercent) external;

    // Set royalty for the given token.
    function setTokenRoyalty(uint256 _tokenId, address _receiver, uint16 _royaltyPercent) external;
}
