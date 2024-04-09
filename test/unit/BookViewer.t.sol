// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/BookManager.sol";
import "../../src/BookViewer.sol";
import "../mocks/BookManagerWrapper.sol";

contract BookViewerTest is Test {
    using TickLibrary for *;
    using FeePolicyLibrary for FeePolicy;

    BookManagerWrapper public bookManager;
    BookViewer public viewer;

    string public base = "12345678901234567890123456789012";

    function setUp() public {
        bookManager = new BookManagerWrapper(address(this), address(0x12312), base, "URI", "name", "SYMBOL");
        viewer = new BookViewer(bookManager);
    }

    function testGetLiquidity(int16 start, uint8[5] memory tickDiff) public {
        BookId id = BookId.wrap(123);

        IBookViewer.Liquidity[] memory liquidity = new IBookViewer.Liquidity[](tickDiff.length + 1);
        liquidity[0] = IBookViewer.Liquidity({tick: Tick.wrap(start), depth: 1});
        bookManager.forceMake(id, liquidity[0].tick, 1);

        for (uint256 i; i < tickDiff.length; i++) {
            Tick tick = Tick.wrap(Tick.unwrap(liquidity[i].tick) + int24(uint24(tickDiff[i])) + 1);
            liquidity[i + 1] = IBookViewer.Liquidity({tick: tick, depth: uint64(i + 2)});
            bookManager.forceMake(id, tick, uint64(i + 2));
        }

        IBookViewer.Liquidity[] memory queried = viewer.getLiquidity(id, Tick.wrap(type(int24).max), tickDiff.length);
        for (uint256 i; i < queried.length; i++) {
            assertEq(Tick.unwrap(queried[i].tick), Tick.unwrap(liquidity[liquidity.length - 1 - i].tick));
            assertEq(queried[i].depth, liquidity[liquidity.length - 1 - i].depth);
        }

        queried = viewer.getLiquidity(id, Tick.wrap(type(int24).max), tickDiff.length - 1);
        for (uint256 i; i < queried.length; i++) {
            assertEq(Tick.unwrap(queried[i].tick), Tick.unwrap(liquidity[liquidity.length - 1 - i].tick));
            assertEq(queried[i].depth, liquidity[liquidity.length - 1 - i].depth);
        }

        queried = viewer.getLiquidity(id, Tick.wrap(type(int24).max), tickDiff.length + 10);
        assertEq(queried.length, liquidity.length, "LENGTH");
        for (uint256 i; i < queried.length; i++) {
            assertEq(Tick.unwrap(queried[i].tick), Tick.unwrap(liquidity[liquidity.length - 1 - i].tick));
            assertEq(queried[i].depth, liquidity[liquidity.length - 1 - i].depth);
        }
    }
}
