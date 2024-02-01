// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../../contracts/libraries/FeePolicy.sol";

contract FeePolicyTest is Test {
    using FeePolicyLibrary for FeePolicy;

    function testEncode(bool usesQuote, int24 rate) public {
        vm.assume(rate <= FeePolicyLibrary.MAX_FEE_RATE && rate >= FeePolicyLibrary.MIN_FEE_RATE);
        FeePolicy feePolicy = FeePolicyLibrary.encode(usesQuote, rate);
        assertEq(feePolicy.usesQuote(), usesQuote);
        assertEq(feePolicy.rate(), rate);
    }

    function testCalculateFee() public {
        _testCalculateFee(true, 1000, 1000000, 1000000, 1000, 0);
        _testCalculateFee(false, 1000, 1000000, 1000000, 0, 1000);
        _testCalculateFee(true, -1000, 1000000, 1000000, -1000, 0);
        _testCalculateFee(false, -1000, 1000000, 1000000, 0, -1000);
        // zero value tests
        _testCalculateFee(true, 0, 1000000, 1000000, 0, 0);
        _testCalculateFee(false, 0, 1000000, 1000000, 0, 0);
        _testCalculateFee(true, 1000, 0, 0, 0, 0);
        _testCalculateFee(false, 1000, 0, 0, 0, 0);
        // rounding tests
        _testCalculateFee(true, 1500, 1000, 1000, 2, 0);
        _testCalculateFee(false, 1500, 1000, 1000, 0, 2);
        _testCalculateFee(true, -1500, 1000, 1000, -1, 0);
        _testCalculateFee(false, -1500, 1000, 1000, 0, -1);
    }

    function _testCalculateFee(bool useQuote, int24 rate, uint256 quote, uint256 base, int256 quoteFee, int256 baseFee)
        private
    {
        FeePolicy feePolicy = FeePolicyLibrary.encode(useQuote, rate);
        (int256 actualQuoteFee, int256 actualBaseFee) = feePolicy.calculateFee(quote, base);
        assertEq(actualQuoteFee, quoteFee);
        assertEq(actualBaseFee, baseFee);
    }
}
