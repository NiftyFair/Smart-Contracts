const { ether } = require('@openzeppelin/test-helpers');

// Set user `seller` variables for `NiftyAuction`
const sellerReservePrice = ether('100');
const sellerNewReservePrice = ether('50'); // 50 WXDAI

// Set user `seller` variables for `NiftyAuction`
const bidderBidAmountMinimum = ether('25'); // 25 WXDAI

module.exports = {
  sellerReservePrice,
  sellerNewReservePrice,
  bidderBidAmountMinimum
};
