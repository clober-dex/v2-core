// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import "./SignificantBit.sol";

library Heap {
    using SignificantBit for uint256;

    error EmptyError();
    error AlreadyExistsError();

    uint256 public constant B0_BITMAP_KEY = uint256(keccak256("Heap"));
    uint256 public constant MAX_UINT_256_MINUS_1 = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe;

    function has(mapping(uint256 => uint256) storage heap, uint24 value) internal view returns (bool) {
        (uint256 b0b1, uint256 b2) = _split(value);
        uint256 mask = 1 << b2;
        return heap[b0b1] & mask == mask;
    }

    function isEmpty(mapping(uint256 => uint256) storage heap) internal view returns (bool) {
        return heap[B0_BITMAP_KEY] == 0;
    }

    function _split(uint24 value) private pure returns (uint256 b0b1, uint8 b2) {
        assembly {
            b2 := value
            b0b1 := shr(8, value)
        }
    }

    function _root(mapping(uint256 => uint256) storage heap) private view returns (uint256 b0b1, uint256 b2) {
        uint256 b0 = heap[B0_BITMAP_KEY].leastSignificantBit();
        b0b1 = (b0 << 8) | (heap[~b0].leastSignificantBit());
        b2 = heap[b0b1].leastSignificantBit();
    }

    function root(mapping(uint256 => uint256) storage heap) internal view returns (uint24) {
        if (isEmpty(heap)) revert EmptyError();

        (uint256 b0b1, uint256 b2) = _root(heap);
        return uint24((b0b1 << 8) | b2);
    }

    function push(mapping(uint256 => uint256) storage heap, uint24 value) internal {
        (uint256 b0b1, uint256 b2) = _split(value);
        uint256 mask = 1 << b2;
        uint256 b2Bitmap = heap[b0b1];
        if (b2Bitmap & mask > 0) {
            revert AlreadyExistsError();
        }

        heap[b0b1] = b2Bitmap | mask;
        if (b2Bitmap == 0) {
            mask = 1 << (b0b1 & 0xff);
            uint256 b1BitmapKey = ~(b0b1 >> 8);
            uint256 b1Bitmap = heap[b1BitmapKey];
            heap[b1BitmapKey] = b1Bitmap | mask;
            if (b1Bitmap == 0) {
                heap[B0_BITMAP_KEY] = heap[B0_BITMAP_KEY] | (1 << ~b1BitmapKey);
            }
        }
    }

    function pop(mapping(uint256 => uint256) storage heap) internal {
        if (isEmpty(heap)) revert EmptyError();

        (uint256 b0b1, uint256 b2) = _root(heap);
        uint256 mask = 1 << b2;
        uint256 b2Bitmap = heap[b0b1];

        heap[b0b1] = b2Bitmap & (~mask);
        if (b2Bitmap == mask) {
            mask = 1 << (b0b1 & 0xff);
            uint256 b1BitmapKey = ~(b0b1 >> 8);
            uint256 b1Bitmap = heap[b1BitmapKey];

            heap[b1BitmapKey] = b1Bitmap & (~mask);
            if (mask == b1Bitmap) {
                mask = 1 << (~b1BitmapKey);
                heap[B0_BITMAP_KEY] = heap[B0_BITMAP_KEY] & (~mask);
            }
        }
    }

    function minGreaterThan(mapping(uint256 => uint256) storage heap, uint24 value) internal view returns (uint24) {
        (uint256 b0b1, uint256 b2) = _split(value);
        uint256 b2Bitmap = (MAX_UINT_256_MINUS_1 << b2) & heap[b0b1];
        if (b2Bitmap == 0) {
            uint256 b0 = b0b1 >> 8;
            uint256 b1Bitmap = (MAX_UINT_256_MINUS_1 << (b0b1 & 0xff)) & heap[~b0];
            if (b1Bitmap == 0) {
                uint256 b0Bitmap = (MAX_UINT_256_MINUS_1 << b0) & heap[B0_BITMAP_KEY];
                if (b0Bitmap == 0) return 0;
                b0 = b0Bitmap.leastSignificantBit();
                b1Bitmap = heap[~b0];
            }
            b0b1 = (b0 << 8) | b1Bitmap.leastSignificantBit();
            b2Bitmap = heap[b0b1];
        }
        b2 = b2Bitmap.leastSignificantBit();
        return uint24((b0b1 << 8) | b2);
    }
}
