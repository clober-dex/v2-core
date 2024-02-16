// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import "./SignificantBit.sol";

library TickBitmap {
    using SignificantBit for uint256;

    error EmptyError();
    error FlipError();

    uint256 public constant B0_BITMAP_KEY = uint256(keccak256("TickBitmap"));
    uint256 public constant MAX_UINT_256_MINUS_1 = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe;

    function has(mapping(uint256 => uint256) storage self, uint24 value) internal view returns (bool) {
        (uint256 b0b1, uint256 mask) = _split(value);
        return self[b0b1] & mask == mask;
    }

    function isEmpty(mapping(uint256 => uint256) storage self) internal view returns (bool) {
        return self[B0_BITMAP_KEY] == 0;
    }

    function _split(uint24 value) private pure returns (uint256 b0b1, uint256 mask) {
        assembly {
            mask := shl(and(value, 0xFF), 1)
            b0b1 := shr(8, value)
        }
    }

    function lowest(mapping(uint256 => uint256) storage self) internal view returns (uint24) {
        if (isEmpty(self)) revert EmptyError();

        uint256 b0 = self[B0_BITMAP_KEY].leastSignificantBit();
        uint256 b0b1 = (b0 << 8) | (self[~b0].leastSignificantBit());
        uint256 b2 = self[b0b1].leastSignificantBit();
        return uint24((b0b1 << 8) | b2);
    }

    function _flip(mapping(uint256 => uint256) storage self, uint24 value, uint256 clear) private {
        (uint256 b0b1, uint256 mask) = _split(value);
        uint256 b2Bitmap = self[b0b1];
        if ((clear ^ b2Bitmap) & mask > 0) revert FlipError();

        self[b0b1] = b2Bitmap ^ mask;
        if (b2Bitmap == clear & mask) {
            mask = 1 << (b0b1 & 0xff);
            uint256 b1BitmapKey = ~(b0b1 >> 8);
            uint256 b1Bitmap = self[b1BitmapKey];
            self[b1BitmapKey] = (b1Bitmap | mask) ^ (clear & mask);

            if (b1Bitmap == clear & mask) {
                mask = 1 << (~b1BitmapKey);
                self[B0_BITMAP_KEY] = (self[B0_BITMAP_KEY] | mask) ^ (clear & mask);
            }
        }
    }

    function set(mapping(uint256 => uint256) storage self, uint24 value) internal {
        _flip(self, value, 0);
    }

    function clear(mapping(uint256 => uint256) storage self, uint24 value) internal {
        _flip(self, value, type(uint256).max);
    }

    function minGreaterThan(mapping(uint256 => uint256) storage self, uint24 value) internal view returns (uint24) {
        uint256 b0b1;
        uint256 b2;
        assembly {
            b2 := and(value, 0xff)
            b0b1 := shr(8, value)
        }
        uint256 b2Bitmap = (MAX_UINT_256_MINUS_1 << b2) & self[b0b1];
        if (b2Bitmap == 0) {
            uint256 b0 = b0b1 >> 8;
            uint256 b1Bitmap = (MAX_UINT_256_MINUS_1 << (b0b1 & 0xff)) & self[~b0];
            if (b1Bitmap == 0) {
                uint256 b0Bitmap = (MAX_UINT_256_MINUS_1 << b0) & self[B0_BITMAP_KEY];
                if (b0Bitmap == 0) return 0;
                b0 = b0Bitmap.leastSignificantBit();
                b1Bitmap = self[~b0];
            }
            b0b1 = (b0 << 8) | b1Bitmap.leastSignificantBit();
            b2Bitmap = self[b0b1];
        }
        b2 = b2Bitmap.leastSignificantBit();
        return uint24((b0b1 << 8) | b2);
    }
}
