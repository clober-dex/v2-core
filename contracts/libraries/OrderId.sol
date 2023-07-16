// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Tick.sol";

type OrderId is uint256;

library OrderIdLibrary {
    function encode(
        uint128 n,
        Tick tick,
        uint256 index
    ) internal pure returns (OrderId id) {
        if (index > type(uint104).max) {
            // TODO: revert
        }
        assembly {
            id := add(index, add(shl(104, tick), shl(128, n)))
        }
    }

    function decode(OrderId id)
        internal
        pure
        returns (
            uint128 n,
            Tick tick,
            uint104 index
        )
    {
        assembly {
            index := id
            tick := shr(104, id)
            n := shr(128, id)
        }
    }
}
