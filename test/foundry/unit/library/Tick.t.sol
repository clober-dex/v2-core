// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../mocks/TickWrapper.sol";

contract TickUnitTest is Test {
    TickWrapper public tickWrapper;

    function setUp() public {
        tickWrapper = new TickWrapper();
    }

    function testIndexToPrice() public {
        uint256 lastPrice = tickWrapper.toPrice(TickLibrary.MIN_TICK);
        int24 tick;
        uint256 price;
        for (int24 index = TickLibrary.MIN_TICK + 1; index < TickLibrary.MAX_TICK; index++) {
            price = tickWrapper.toPrice(index);

            tick = tickWrapper.fromPrice(price - 1);
            assertEq(tick, index - 1, "LOWER_PRICE");

            tick = tickWrapper.fromPrice(price);
            assertEq(tick, index, "EXACT_PRICE");

            tick = tickWrapper.fromPrice(price + 1);
            assertEq(tick, index, "HIGHER_PRICE");

            uint256 spread = (price - lastPrice) * 1000000 / lastPrice;
            assertGe(spread, 50);
            assertLe(spread, 200);
            lastPrice = price;
        }
    }
}
