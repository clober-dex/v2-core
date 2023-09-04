// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@clober/library/contracts/DirtyUint64.sol";
import "@clober/library/contracts/PackedUint256.sol";

import "./Tick.sol";

library TotalClaimableMap {
    using DirtyUint64 for uint64;
    using PackedUint256 for uint256;

    function add(mapping(uint24 => uint256) storage self, Tick tick, uint64 n) internal {
        // TODO: add
        // @notice Be aware of dirty storage add logic
    }

    function sub(mapping(uint24 => uint256) storage self, Tick tick, uint64 n) internal {
        // TODO: sub
    }

    function get(mapping(uint24 => uint256) storage self, Tick tick) internal view returns (uint64) {
        (uint24 groupIndex, uint8 elementIndex) = _splitTick(tick);
        return self[groupIndex].get64Unsafe(elementIndex).toClean();
    }

    function _splitTick(Tick tick) internal pure returns (uint24 groupIndex, uint8 elementIndex) {
        uint256 casted = Tick.unwrap(tick);
        assembly {
            groupIndex := shr(2, casted) // div 4
            elementIndex := and(casted, 3) // mod 4
        }
    }
}
