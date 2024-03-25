// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE_V2.pdf

pragma solidity ^0.8.20;

import {DirtyUint64} from "./DirtyUint64.sol";
import {PackedUint256} from "./PackedUint256.sol";
import {Tick} from "./Tick.sol";

library TotalClaimableMap {
    using DirtyUint64 for uint64;
    using PackedUint256 for uint256;

    // @dev n should be less than type(uint64).max due to the dirty storage logic.
    function add(mapping(uint24 => uint256) storage self, Tick tick, uint64 n) internal {
        (uint24 groupIndex, uint8 elementIndex) = _splitTick(tick);
        uint256 group = self[groupIndex];
        // @notice Be aware of dirty storage add logic
        self[groupIndex] = group.update64Unsafe(
            elementIndex, // elementIndex < 4
            group.get64Unsafe(elementIndex).addClean(n)
        );
    }

    function sub(mapping(uint24 => uint256) storage self, Tick tick, uint64 n) internal {
        (uint24 groupIndex, uint8 elementIndex) = _splitTick(tick);
        self[groupIndex] = self[groupIndex].sub64Unsafe(elementIndex, n);
    }

    function get(mapping(uint24 => uint256) storage self, Tick tick) internal view returns (uint64) {
        (uint24 groupIndex, uint8 elementIndex) = _splitTick(tick);
        return self[groupIndex].get64Unsafe(elementIndex).toClean();
    }

    function _splitTick(Tick tick) internal pure returns (uint24 groupIndex, uint8 elementIndex) {
        uint256 casted = uint24(Tick.unwrap(tick));
        assembly {
            groupIndex := shr(2, casted) // div 4
            elementIndex := and(casted, 3) // mod 4
        }
    }
}
