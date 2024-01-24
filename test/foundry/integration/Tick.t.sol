// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../mocks/TickWrapper.sol";

contract TickUnitTest is Test {
    TickWrapper public tickWrapper;

    function setUp() public {
        tickWrapper = new TickWrapper();
    }

    function testTickToPrice(int24 index) public {
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
}
