// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../src/libraries/FeePolicy.sol";

contract FeePolicyTest is Test {
    using FeePolicyLibrary for FeePolicy;

    function testEncode(bool usesQuote, int24 rate) public pure {
        vm.assume(rate <= FeePolicyLibrary.MAX_FEE_RATE && rate >= FeePolicyLibrary.MIN_FEE_RATE);
        FeePolicy feePolicy = FeePolicyLibrary.encode(usesQuote, rate);
        assertEq(feePolicy.usesQuote(), usesQuote);
        assertEq(feePolicy.rate(), rate);
    }

    function testCalculateFee() public pure {
        _testCalculateFee(1000, 1000000, 1000, false);
        _testCalculateFee(-1000, 1000000, -1000, false);
        // zero value tests
        _testCalculateFee(0, 1000000, 0, false);
        _testCalculateFee(1000, 0, 0, false);
        // rounding tests
        _testCalculateFee(1500, 1000, 2, false);
        _testCalculateFee(-1500, 1000, -1, false);
        _testCalculateFee(1500, 1000, 1, true);
        _testCalculateFee(-1500, 1000, -2, true);
    }

    function _testCalculateFee(int24 rate, int256 amount, int256 fee, bool reverse) private pure {
        FeePolicy feePolicy = FeePolicyLibrary.encode(true, rate);
        int256 actualFee = feePolicy.calculateFee(uint256(amount), reverse);
        assertEq(actualFee, fee);
        if (!reverse) {
            assertEq(feePolicy.calculateOriginalAmount(uint256(amount + actualFee), false), uint256(amount));
            assertEq(feePolicy.calculateOriginalAmount(uint256(amount - actualFee), true), uint256(amount));
        }
    }
}
