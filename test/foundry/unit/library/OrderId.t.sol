// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../../contracts/libraries/OrderId.sol";

contract OrderIdUnitTest is Test {
    using OrderIdLibrary for OrderId;

    function testEncode() public {
        OrderId id = OrderIdLibrary.encode(BookId.wrap(1), Tick.wrap(2), 3);
        assertEq(OrderId.unwrap(id), 0x10000020000000003);
        id = OrderIdLibrary.encode(BookId.wrap(1), Tick.wrap(-2), 3);
        assertEq(OrderId.unwrap(id), 0x1fffffe0000000003);
    }

    function testDecode() public {
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
}
