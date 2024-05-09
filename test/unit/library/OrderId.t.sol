// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../src/libraries/OrderId.sol";

contract OrderIdUnitTest is Test {
    using OrderIdLibrary for OrderId;

    function testEncode() public pure {
        OrderId id = OrderIdLibrary.encode(BookId.wrap(1), Tick.wrap(2), 3);
        assertEq(OrderId.unwrap(id), 0x10000020000000003);
        id = OrderIdLibrary.encode(BookId.wrap(1), Tick.wrap(-2), 3);
        assertEq(OrderId.unwrap(id), 0x1fffffe0000000003);
    }

    function testDecode() public pure {
        OrderId id = OrderId.wrap(0x10000020000000003);
        BookId bookId;
        Tick tick;
        uint40 index;
        (bookId, tick, index) = id.decode();
        assertEq(BookId.unwrap(bookId), uint192(1));
        assertEq(Tick.unwrap(tick), int24(2));
        assertEq(index, uint40(3));
        id = OrderId.wrap(0x1fffffe0000000003);
        (bookId, tick, index) = id.decode();
        assertEq(BookId.unwrap(bookId), uint192(1));
        assertEq(Tick.unwrap(tick), int24(-2));
        assertEq(index, uint40(3));
    }

    function testEncodeAndDecode(BookId bookId, Tick tick, uint40 index) public pure {
        OrderId id = OrderIdLibrary.encode(bookId, tick, index);
        BookId _bookId;
        Tick _tick;
        uint40 _index;
        (_bookId, _tick, _index) = id.decode();
        assertEq(BookId.unwrap(_bookId), BookId.unwrap(bookId));
        assertEq(Tick.unwrap(_tick), Tick.unwrap(tick));
        assertEq(_index, index);
    }
}
