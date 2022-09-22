// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
     @notice Very simple price oracle for wxdai
*/

contract NiftyPriceOracle is Ownable {
    uint8 curentDecimals = 8;
    int256 currentLatestAnswer = 100000000;

    function decimals() external view returns (uint8) {
        return curentDecimals;
    }

    function latestAnswer() public view virtual returns (int256 answer) {
        return currentLatestAnswer;
    }

    function update(uint8 _curentDecimals, int256 _currentLatestAnswer)
        external
        onlyOwner
    {
        curentDecimals = _curentDecimals;
        currentLatestAnswer = _currentLatestAnswer;
    }
}
