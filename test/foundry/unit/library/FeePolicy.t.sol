// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../../contracts/libraries/FeePolicy.sol";

contract FeePolicyTest is Test {
    using FeePolicyLibrary for FeePolicy;

    function testEncode(bool usesQuote, int24 rate) public {
        vm.assume(rate <= FeePolicyLibrary.MAX_FEE_RATE && rate >= FeePolicyLibrary.MIN_FEE_RATE);
        FeePolicy feePolicy = FeePolicyLibrary.encode(usesQuote, rate);
        console.log(FeePolicy.unwrap(feePolicy));
        console.logBytes3(bytes3(uint24(FeePolicy.unwrap(feePolicy))));
        assertEq(feePolicy.usesQuote(), usesQuote);
        assertEq(feePolicy.rate(), rate);
    }
}
