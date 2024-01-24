// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import "./SignificantBit.sol";

library Math {
    using SignificantBit for uint256;

    function divide(uint256 a, uint256 b, bool roundingUp) internal pure returns (uint256 ret) {
        // In the OrderBook contract code, b is never zero.
        assembly {
            ret := add(div(a, b), and(gt(mod(a, b), 0), roundingUp))
        }
    }

    function log2(uint256 x) internal pure returns (int256) {
        require(x > 0);

        uint8 msb = x.mostSignificantBit();

        if (msb > 128) x >>= msb - 128;
        else if (msb < 128) x <<= 128 - msb;

        x &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

        int256 result = (int256(uint256(msb)) - 128) << 128; // Integer part of log_2

        int256 bit = 0x80000000000000000000000000000000;
        for (uint8 i = 0; i < 128 && x > 0; i++) {
            x = (x << 1) + ((x * x + 0x80000000000000000000000000000000) >> 128);
            if (x > 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
                result |= bit;
                x = (x >> 1) - 0x80000000000000000000000000000000;
            }
            bit >>= 1;
        }

        return result;
    }
}
