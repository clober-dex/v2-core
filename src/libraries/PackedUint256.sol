// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

library PackedUint256 {
    error PackedUint256Error(uint256 errorCode);

    uint256 private constant _UINT8_INDEX_ERROR = 0;
    uint256 private constant _UINT16_INDEX_ERROR = 1;
    uint256 private constant _UINT32_INDEX_ERROR = 2;
    uint256 private constant _UINT64_INDEX_ERROR = 3;

    uint256 private constant _MAX_UINT64 = type(uint64).max;
    uint256 private constant _MAX_UINT32 = type(uint32).max;
    uint256 private constant _MAX_UINT16 = type(uint16).max;
    uint256 private constant _MAX_UINT8 = type(uint8).max;

    function get8Unsafe(uint256 packed, uint256 index) internal pure returns (uint8 ret) {
        assembly {
            ret := and(shr(shl(3, index), packed), 0xff)
        }
    }

    function get8(uint256 packed, uint256 index) internal pure returns (uint8 ret) {
        if (index > 31) {
            revert PackedUint256Error(_UINT8_INDEX_ERROR);
        }
        assembly {
            ret := and(shr(shl(3, index), packed), 0xff)
        }
    }

    function get16Unsafe(uint256 packed, uint256 index) internal pure returns (uint16 ret) {
        assembly {
            ret := and(shr(shl(4, index), packed), 0xffff)
        }
    }

    function get16(uint256 packed, uint256 index) internal pure returns (uint16 ret) {
        if (index > 15) {
            revert PackedUint256Error(_UINT16_INDEX_ERROR);
        }
        assembly {
            ret := and(shr(shl(4, index), packed), 0xffff)
        }
    }

    function get32Unsafe(uint256 packed, uint256 index) internal pure returns (uint32 ret) {
        assembly {
            ret := and(shr(shl(5, index), packed), 0xffffffff)
        }
    }

    function get32(uint256 packed, uint256 index) internal pure returns (uint32 ret) {
        if (index > 7) {
            revert PackedUint256Error(_UINT32_INDEX_ERROR);
        }
        assembly {
            ret := and(shr(shl(5, index), packed), 0xffffffff)
        }
    }

    function get64Unsafe(uint256 packed, uint256 index) internal pure returns (uint64 ret) {
        assembly {
            ret := and(shr(shl(6, index), packed), 0xffffffffffffffff)
        }
    }

    function get64(uint256 packed, uint256 index) internal pure returns (uint64 ret) {
        if (index > 3) {
            revert PackedUint256Error(_UINT64_INDEX_ERROR);
        }
        assembly {
            ret := and(shr(shl(6, index), packed), 0xffffffffffffffff)
        }
    }

    function add8Unsafe(uint256 packed, uint256 index, uint8 value) internal pure returns (uint256 ret) {
        assembly {
            ret := add(packed, shl(shl(3, index), and(value, 0xff)))
        }
    }

    function add8(uint256 packed, uint256 index, uint8 value) internal pure returns (uint256 ret) {
        if (index > 31) {
            revert PackedUint256Error(_UINT8_INDEX_ERROR);
        }
        uint8 current = get8Unsafe(packed, index);
        current += value;
        ret = update8Unsafe(packed, index, current);
    }

    function add16Unsafe(uint256 packed, uint256 index, uint16 value) internal pure returns (uint256 ret) {
        assembly {
            ret := add(packed, shl(shl(4, index), and(value, 0xffff)))
        }
    }

    function add16(uint256 packed, uint256 index, uint16 value) internal pure returns (uint256 ret) {
        if (index > 15) {
            revert PackedUint256Error(_UINT16_INDEX_ERROR);
        }
        uint16 current = get16Unsafe(packed, index);
        current += value;
        ret = update16Unsafe(packed, index, current);
    }

    function add32Unsafe(uint256 packed, uint256 index, uint32 value) internal pure returns (uint256 ret) {
        assembly {
            ret := add(packed, shl(shl(5, index), and(value, 0xffffffff)))
        }
    }

    function add32(uint256 packed, uint256 index, uint32 value) internal pure returns (uint256 ret) {
        if (index > 7) {
            revert PackedUint256Error(_UINT32_INDEX_ERROR);
        }
        uint32 current = get32Unsafe(packed, index);
        current += value;
        ret = update32Unsafe(packed, index, current);
    }

    function add64Unsafe(uint256 packed, uint256 index, uint64 value) internal pure returns (uint256 ret) {
        assembly {
            ret := add(packed, shl(shl(6, index), and(value, 0xffffffffffffffff)))
        }
    }

    function add64(uint256 packed, uint256 index, uint64 value) internal pure returns (uint256 ret) {
        if (index > 3) {
            revert PackedUint256Error(_UINT64_INDEX_ERROR);
        }
        uint64 current = get64Unsafe(packed, index);
        current += value;
        ret = update64Unsafe(packed, index, current);
    }

    function sub8Unsafe(uint256 packed, uint256 index, uint8 value) internal pure returns (uint256 ret) {
        assembly {
            ret := sub(packed, shl(shl(3, index), and(value, 0xff)))
        }
    }

    function sub8(uint256 packed, uint256 index, uint8 value) internal pure returns (uint256 ret) {
        if (index > 31) {
            revert PackedUint256Error(_UINT8_INDEX_ERROR);
        }
        uint8 current = get8Unsafe(packed, index);
        current -= value;
        ret = update8Unsafe(packed, index, current);
    }

    function sub16Unsafe(uint256 packed, uint256 index, uint16 value) internal pure returns (uint256 ret) {
        assembly {
            ret := sub(packed, shl(shl(4, index), and(value, 0xffff)))
        }
    }

    function sub16(uint256 packed, uint256 index, uint16 value) internal pure returns (uint256 ret) {
        if (index > 15) {
            revert PackedUint256Error(_UINT16_INDEX_ERROR);
        }
        uint16 current = get16Unsafe(packed, index);
        current -= value;
        ret = update16Unsafe(packed, index, current);
    }

    function sub32Unsafe(uint256 packed, uint256 index, uint32 value) internal pure returns (uint256 ret) {
        assembly {
            ret := sub(packed, shl(shl(5, index), and(value, 0xffffffff)))
        }
    }

    function sub32(uint256 packed, uint256 index, uint32 value) internal pure returns (uint256 ret) {
        if (index > 7) {
            revert PackedUint256Error(_UINT32_INDEX_ERROR);
        }
        uint32 current = get32Unsafe(packed, index);
        current -= value;
        ret = update32Unsafe(packed, index, current);
    }

    function sub64Unsafe(uint256 packed, uint256 index, uint64 value) internal pure returns (uint256 ret) {
        assembly {
            ret := sub(packed, shl(shl(6, index), and(value, 0xffffffffffffffff)))
        }
    }

    function sub64(uint256 packed, uint256 index, uint64 value) internal pure returns (uint256 ret) {
        if (index > 3) {
            revert PackedUint256Error(_UINT64_INDEX_ERROR);
        }
        uint64 current = get64Unsafe(packed, index);
        current -= value;
        ret = update64Unsafe(packed, index, current);
    }

    function update8Unsafe(uint256 packed, uint256 index, uint8 value) internal pure returns (uint256 ret) {
        unchecked {
            index = index << 3;
            packed = packed - (packed & (_MAX_UINT8 << index));
        }
        assembly {
            ret := add(packed, shl(index, and(value, 0xff)))
        }
    }

    function update8(uint256 packed, uint256 index, uint8 value) internal pure returns (uint256 ret) {
        if (index > 31) {
            revert PackedUint256Error(_UINT8_INDEX_ERROR);
        }
        unchecked {
            index = index << 3;
            packed = packed - (packed & (_MAX_UINT8 << index));
        }
        assembly {
            ret := add(packed, shl(index, and(value, 0xff)))
        }
    }

    function update16Unsafe(uint256 packed, uint256 index, uint16 value) internal pure returns (uint256 ret) {
        unchecked {
            index = index << 4;
            packed = packed - (packed & (_MAX_UINT16 << index));
        }
        assembly {
            ret := add(packed, shl(index, and(value, 0xffff)))
        }
    }

    function update16(uint256 packed, uint256 index, uint16 value) internal pure returns (uint256 ret) {
        if (index > 15) {
            revert PackedUint256Error(_UINT16_INDEX_ERROR);
        }
        unchecked {
            index = index << 4;
            packed = packed - (packed & (_MAX_UINT16 << index));
        }
        assembly {
            ret := add(packed, shl(index, and(value, 0xffff)))
        }
    }

    function update32Unsafe(uint256 packed, uint256 index, uint32 value) internal pure returns (uint256 ret) {
        unchecked {
            index = index << 5;
            packed = packed - (packed & (_MAX_UINT32 << index));
        }
        assembly {
            ret := add(packed, shl(index, and(value, 0xffffffff)))
        }
    }

    function update32(uint256 packed, uint256 index, uint32 value) internal pure returns (uint256 ret) {
        if (index > 7) {
            revert PackedUint256Error(_UINT32_INDEX_ERROR);
        }
        unchecked {
            index = index << 5;
            packed = packed - (packed & (_MAX_UINT32 << index));
        }
        assembly {
            ret := add(packed, shl(index, and(value, 0xffffffff)))
        }
    }

    function update64Unsafe(uint256 packed, uint256 index, uint64 value) internal pure returns (uint256 ret) {
        unchecked {
            index = index << 6;
            packed = packed - (packed & (_MAX_UINT64 << index));
        }
        assembly {
            ret := add(packed, shl(index, and(value, 0xffffffffffffffff)))
        }
    }

    function update64(uint256 packed, uint256 index, uint64 value) internal pure returns (uint256 ret) {
        if (index > 3) {
            revert PackedUint256Error(_UINT64_INDEX_ERROR);
        }
        unchecked {
            index = index << 6;
            packed = packed - (packed & (_MAX_UINT64 << index));
        }
        assembly {
            ret := add(packed, shl(index, and(value, 0xffffffffffffffff)))
        }
    }

    function total32(uint256 packed) internal pure returns (uint256) {
        unchecked {
            uint256 ret = _MAX_UINT32 & packed;
            for (uint256 i = 0; i < 7; ++i) {
                packed = packed >> 32;
                ret += _MAX_UINT32 & packed;
            }
            return ret;
        }
    }

    function total64(uint256 packed) internal pure returns (uint256) {
        unchecked {
            uint256 ret = _MAX_UINT64 & packed;
            for (uint256 i = 0; i < 3; ++i) {
                packed = packed >> 64;
                ret += _MAX_UINT64 & packed;
            }
            return ret;
        }
    }

    function sum32(uint256 packed, uint256 from, uint256 to) internal pure returns (uint256) {
        unchecked {
            packed = packed >> (from << 5);
            uint256 ret = 0;
            for (uint256 i = from; i < to; ++i) {
                ret += _MAX_UINT32 & packed;
                packed = packed >> 32;
            }
            return ret;
        }
    }

    function sum64(uint256 packed, uint256 from, uint256 to) internal pure returns (uint256) {
        unchecked {
            packed = packed >> (from << 6);
            uint256 ret = 0;
            for (uint256 i = from; i < to; ++i) {
                ret += _MAX_UINT64 & packed;
                packed = packed >> 64;
            }
            return ret;
        }
    }
}
