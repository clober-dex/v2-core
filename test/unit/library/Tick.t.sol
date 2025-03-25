// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../mocks/TickWrapper.sol";

contract TickUnitTest is Test {
    using TickLibrary for *;

    TickWrapper public tickWrapper;

    function setUp() public {
        tickWrapper = new TickWrapper();
    }

    function testTickToPrice(int24 index) public view {
        vm.assume(index > TickLibrary.MIN_TICK && index < TickLibrary.MAX_TICK);

        uint256 price = tickWrapper.toPrice(index);

        int24 tick = tickWrapper.fromPrice(price - 1);
        assertEq(tick, index - 1, "LOWER_PRICE");

        tick = tickWrapper.fromPrice(price);
        assertEq(tick, index, "EXACT_PRICE");

        tick = tickWrapper.fromPrice(price + 1);
        assertEq(tick, index, "HIGHER_PRICE");

        uint256 spread = (price - tickWrapper.toPrice(index - 1)) * 1000000 / price;
        assertGe(spread, 99);
        assertLe(spread, 100);
    }

    //    function testMinTickToPrice() public {
    //        uint256 lastPrice = tickWrapper.toPrice(TickLibrary.MIN_TICK);
    //
    //        vm.expectRevert(abi.encodeWithSelector(TickLibrary.InvalidPrice.selector));
    //        tickWrapper.fromPrice(lastPrice - 1);
    //
    //        int24 tick = tickWrapper.fromPrice(lastPrice);
    //        assertEq(tick, TickLibrary.MIN_TICK, "MIN_PRICE");
    //
    //        tick = tickWrapper.fromPrice(lastPrice + 1);
    //        assertEq(tick, TickLibrary.MIN_TICK, "MIN_PRICE");
    //
    //        for (int24 index = TickLibrary.MIN_TICK + 1; index < TickLibrary.MIN_TICK + 100000; index++) {
    //            uint256 price = tickWrapper.toPrice(index);
    //
    //            tick = tickWrapper.fromPrice(price - 1);
    //            assertEq(tick, index - 1, "LOWER_PRICE");
    //
    //            tick = tickWrapper.fromPrice(price);
    //            assertEq(tick, index, "EXACT_PRICE");
    //
    //            tick = tickWrapper.fromPrice(price + 1);
    //            assertEq(tick, index, "HIGHER_PRICE");
    //
    //            uint256 spread = (price - lastPrice) * 1000000 / lastPrice;
    //            assertGe(spread, 99);
    //            assertLe(spread, 100);
    //            lastPrice = price;
    //        }
    //    }
    //
    //    function testMiddleTickToPrice() public view {
    //        uint256 lastPrice = tickWrapper.toPrice(-100001);
    //
    //        for (int24 index = -100000; index < 100000; index++) {
    //            uint256 price = tickWrapper.toPrice(index);
    //
    //            int24 tick = tickWrapper.fromPrice(price - 1);
    //            assertEq(tick, index - 1, "LOWER_PRICE");
    //
    //            tick = tickWrapper.fromPrice(price);
    //            assertEq(tick, index, "EXACT_PRICE");
    //
    //            tick = tickWrapper.fromPrice(price + 1);
    //            assertEq(tick, index, "HIGHER_PRICE");
    //
    //            uint256 spread = (price - lastPrice) * 1000000 / lastPrice;
    //            assertGe(spread, 99);
    //            assertLe(spread, 100);
    //            lastPrice = price;
    //        }
    //    }
    //
    //    function testMaxTickToPrice() public {
    //        uint256 lastPrice = tickWrapper.toPrice(TickLibrary.MAX_TICK);
    //
    //        vm.expectRevert(abi.encodeWithSelector(TickLibrary.InvalidPrice.selector));
    //        tickWrapper.fromPrice(lastPrice + 1);
    //
    //        int24 tick = tickWrapper.fromPrice(lastPrice);
    //        assertEq(tick, TickLibrary.MAX_TICK, "MAX_PRICE");
    //
    //        tick = tickWrapper.fromPrice(lastPrice - 1);
    //        assertEq(tick, TickLibrary.MAX_TICK - 1, "MAX_PRICE");
    //
    //        for (int24 index = TickLibrary.MAX_TICK - 1; index < TickLibrary.MAX_TICK - 100000; index--) {
    //            uint256 price = tickWrapper.toPrice(index);
    //
    //            tick = tickWrapper.fromPrice(price - 1);
    //            assertEq(tick, index - 1, "LOWER_PRICE");
    //
    //            tick = tickWrapper.fromPrice(price);
    //            assertEq(tick, index, "EXACT_PRICE");
    //
    //            tick = tickWrapper.fromPrice(price + 1);
    //            assertEq(tick, index, "HIGHER_PRICE");
    //
    //            uint256 spread = (lastPrice - price) * 1000000 / lastPrice;
    //            assertGe(spread, 99);
    //            assertLe(spread, 100);
    //            lastPrice = price;
    //        }
    //    }

    //    // Have to check all ticks is validate.
    //    function testTickToPrice() public {
    //        uint256 lastPrice = tickWrapper.toPrice(TickLibrary.MIN_TICK);
    //        int24 tick;
    //        uint256 price;
    //        for (int24 index = TickLibrary.MIN_TICK + 1; index < TickLibrary.MAX_TICK; index++) {
    //            price = tickWrapper.toPrice(index);
    //
    //            tick = tickWrapper.fromPrice(price - 1);
    //            assertEq(tick, index - 1, "LOWER_PRICE");
    //
    //            tick = tickWrapper.fromPrice(price);
    //            assertEq(tick, index, "EXACT_PRICE");
    //
    //            tick = tickWrapper.fromPrice(price + 1);
    //            assertEq(tick, index, "HIGHER_PRICE");
    //
    //            uint256 spread = (price - lastPrice) * 1000000 / lastPrice;
    //            assertGe(spread, 99);
    //            assertLe(spread, 100);
    //            lastPrice = price;
    //        }
    //    }
}
