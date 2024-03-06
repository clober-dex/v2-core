// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./Tick.sol";
import "./BookId.sol";

type OrderId is uint256;

library OrderIdLibrary {
    /**
     * @dev Encode the order id.
     * @param bookId The book id.
     * @param tick The tick.
     * @param index The index.
     * @return id The order id.
     */
    function encode(BookId bookId, Tick tick, uint40 index) internal pure returns (OrderId id) {
        // @dev If we just use tick at the assembly code, the code will convert tick into bytes32.
        //      e.g. When index == -2, the shifted value( shl(40, tick) ) will be
        //      0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0000000000 instead of 0xfffffffe0000000000
        //      Therefore, we have to safely cast tick into uint256 first.
        uint256 _tick = uint256(uint24(Tick.unwrap(tick)));
        assembly {
            id := add(index, add(shl(40, _tick), shl(64, bookId)))
        }
    }

    function decode(OrderId id) internal pure returns (BookId bookId, Tick tick, uint40 index) {
        assembly {
            bookId := shr(64, id)
            tick := shr(40, id)
            index := id
        }
    }

    function getBookId(OrderId id) internal pure returns (BookId bookId) {
        assembly {
            bookId := shr(64, id)
        }
    }
}
