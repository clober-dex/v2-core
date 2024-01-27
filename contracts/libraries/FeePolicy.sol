// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./Math.sol";

type FeePolicy is uint24;

library FeePolicyLibrary {
    int256 internal constant RATE_PRECISION = 10 ** 6;
    int256 internal constant MAX_FEE_RATE = 500000;
    int256 internal constant MIN_FEE_RATE = -500000;

    uint256 internal constant RATE_MASK = 0x0fffff; // 20 bits

    error InvalidFeePolicy();

    function encode(bool useOutput_, int24 rate_) internal pure returns (FeePolicy feePolicy) {
        if (rate_ > MAX_FEE_RATE || rate_ < MIN_FEE_RATE) {
            revert InvalidFeePolicy();
        }

        assembly {
            feePolicy := or(shl(21, useOutput_), add(rate_, MAX_FEE_RATE))
        }
    }

    function isValid(FeePolicy self) internal pure returns (bool) {
        int24 r = rate(self);

        return !(r > MAX_FEE_RATE || r < MIN_FEE_RATE);
    }

    function useOutput(FeePolicy self) internal pure returns (bool f) {
        assembly {
            f := shr(21, self)
        }
    }

    function rate(FeePolicy self) internal pure returns (int24 r) {
        assembly {
            r := sub(and(self, RATE_MASK), MAX_FEE_RATE)
        }
    }
}
