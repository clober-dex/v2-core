// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Tick.sol";
import "./BookId.sol";

type OrderId is uint256;

library OrderIdLibrary {
    function encode(
        BookId bookId,
        Tick tick,
        uint40 index
    ) internal pure returns (OrderId id) {
        assembly {
            id := add(index, add(shl(40, tick), shl(64, bookId)))
        }
    }

    function decode(OrderId id)
        internal
        pure
        returns (
            BookId bookId,
            Tick tick,
            uint40 index
        )
    {
        assembly {
            bookId := shr(64, id)
            tick := shr(40, id)
            index := id
        }
    }
}
