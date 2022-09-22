pragma solidity ^0.8.0;

interface IOracle {
    function decimals() external view returns (uint8);

    function latestAnswer() external view returns (int256);
}

contract MockPriceOracleProxy is IOracle {
    int256 price;
    uint8 decimal;

    function latestAnswer() external view override returns (int256) {
        return price;
    }

    function decimals() external view override returns (uint8) {
        return decimal;
    }
}
