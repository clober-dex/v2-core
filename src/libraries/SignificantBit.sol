// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

library SignificantBit {
    // http://supertech.csail.mit.edu/papers/debruijn.pdf
    uint256 internal constant DEBRUIJN_SEQ = 0x818283848586878898A8B8C8D8E8F929395969799A9B9D9E9FAAEB6BEDEEFF;
    bytes internal constant DEBRUIJN_INDEX =
        hex"0001020903110a19042112290b311a3905412245134d2a550c5d32651b6d3a7506264262237d468514804e8d2b95569d0d495ea533a966b11c886eb93bc176c9071727374353637324837e9b47af86c7155181ad4fd18ed32c9096db57d59ee30e2e4a6a5f92a6be3498aae067ddb2eb1d5989b56fd7baf33ca0c2ee77e5caf7ff0810182028303840444c545c646c7425617c847f8c949c48a4a8b087b8c0c816365272829aaec650acd0d28fdad4e22d6991bd97dfdcea58b4d6f29fede4f6fe0f1f2f3f4b5b6b607b8b93a3a7b7bf357199c5abcfd9e168bcdee9b3f1ecf5fd1e3e5a7a8aa2b670c4ced8bbe8f0f4fc3d79a1c3cde7effb78cce6facbf9f8";

    /**
     * @notice Finds the index of the least significant bit.
     * @param x The value to compute the least significant bit for. Must be a non-zero value.
     * @return ret The index of the least significant bit.
     */
    function leastSignificantBit(uint256 x) internal pure returns (uint8) {
        require(x > 0);
        uint256 index;
        assembly {
            index := shr(248, mul(and(x, add(not(x), 1)), DEBRUIJN_SEQ))
        }
        return uint8(DEBRUIJN_INDEX[index]); // can optimize with CODECOPY opcode
    }

    function mostSignificantBit(uint256 x) internal pure returns (uint8) {
        require(x > 0);
        uint256 msb;
        assembly {
            let f := shl(7, gt(x, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            x := shr(f, x)
            f := shl(6, gt(x, 0xFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            x := shr(f, x)
            f := shl(5, gt(x, 0xFFFFFFFF))
            msb := or(msb, f)
            x := shr(f, x)
            f := shl(4, gt(x, 0xFFFF))
            msb := or(msb, f)
            x := shr(f, x)
            f := shl(3, gt(x, 0xFF))
            msb := or(msb, f)
            x := shr(f, x)
            f := shl(2, gt(x, 0xF))
            msb := or(msb, f)
            x := shr(f, x)
            f := shl(1, gt(x, 0x3))
            msb := or(msb, f)
            x := shr(f, x)
            f := gt(x, 0x1)
            msb := or(msb, f)
        }
        return uint8(msb);
    }
}
