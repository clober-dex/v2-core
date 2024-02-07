// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../contracts/BookManager.sol";
import "../../../contracts/BookViewer.sol";
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

    function testBaseURI(string memory randomURI) public {
        bookManager.setBaseURI(randomURI);
        string memory b = viewer.baseURI();
        assertEq(keccak256(abi.encodePacked(b)), keccak256(abi.encodePacked(randomURI)));
    }

    function testContractURI(string memory randomURI) public {
        bookManager.setContractURI(randomURI);
        string memory b = viewer.contractURI();
        assertEq(keccak256(abi.encodePacked(b)), keccak256(abi.encodePacked(randomURI)));
    }

    function testDefaultProvider(address randomProvider) public {
        bookManager.setDefaultProvider(randomProvider);
        address b = viewer.defaultProvider();
        assertEq(b, randomProvider);
    }

    function testCurrencyDelta(address locker, Currency currency, int256 delta) public {
        bookManager.setCurrencyDelta(locker, currency, delta);
        int256 b = viewer.currencyDelta(locker, currency);
        assertEq(b, delta);
    }

    function testReservesOf(Currency currency, uint256 reserves) public {
        bookManager.setReservesOf(currency, reserves);
        uint256 b = viewer.reservesOf(currency);
        assertEq(b, reserves);
    }

    function testGetBookKey(BookId bookId, IBookManager.BookKey memory key) public {
        bookManager.setBookKey(bookId, key);
        IBookManager.BookKey memory b = viewer.getBookKey(bookId);
        assertEq(Currency.unwrap(b.base), Currency.unwrap(key.base));
        assertEq(b.unit, key.unit);
        assertEq(Currency.unwrap(b.quote), Currency.unwrap(key.quote));
        assertEq(b.makerPolicy.rate(), key.makerPolicy.rate());
        assertEq(b.makerPolicy.usesQuote(), key.makerPolicy.usesQuote());
        assertEq(b.takerPolicy.rate(), key.takerPolicy.rate());
        assertEq(b.takerPolicy.usesQuote(), key.takerPolicy.usesQuote());
        assertEq(address(b.hooks), address(key.hooks));
    }

    function testIsWhitelisted(address provider, bool whitelisted) public {
        bookManager.setWhitelisted(provider, whitelisted);
        bool b = viewer.isWhitelisted(provider);
        assertEq(b, whitelisted);
    }

    function testTokenOwed(address provider, Currency currency, uint256 tokenOwed) public {
        bookManager.setTokenOwed(provider, currency, tokenOwed);
        uint256 b = viewer.tokenOwed(provider, currency);
        assertEq(b, tokenOwed);
    }

    function testGetLiquidity(int16 start, uint8[22] memory tickDiff) public {
        BookId id = BookId.wrap(123);

        IBookViewer.Liquidity[] memory liquidity = new IBookViewer.Liquidity[](tickDiff.length + 1);
        liquidity[0] = IBookViewer.Liquidity({tick: Tick.wrap(start), depth: 1});
        bookManager.forceMake(id, liquidity[0].tick, 1);

        for (uint256 i; i < tickDiff.length; i++) {
            Tick tick = Tick.wrap(Tick.unwrap(liquidity[i].tick) + int24(uint24(tickDiff[i])) + 1);
            liquidity[i + 1] = IBookViewer.Liquidity({tick: tick, depth: uint64(i + 2)});
            bookManager.forceMake(id, tick, uint64(i + 2));
        }

        IBookViewer.Liquidity[] memory queried = viewer.getLiquidity(id, Tick.wrap(type(int24).min), tickDiff.length);
        for (uint256 i; i < queried.length; i++) {
            assertEq(Tick.unwrap(queried[i].tick), Tick.unwrap(liquidity[i].tick));
            assertEq(queried[i].depth, liquidity[i].depth);
        }

        queried = viewer.getLiquidity(id, Tick.wrap(type(int24).min), tickDiff.length - 1);
        for (uint256 i; i < queried.length; i++) {
            assertEq(Tick.unwrap(queried[i].tick), Tick.unwrap(liquidity[i].tick));
            assertEq(queried[i].depth, liquidity[i].depth);
        }

        queried = viewer.getLiquidity(id, Tick.wrap(type(int24).min), tickDiff.length + 10);
        for (uint256 i; i < queried.length; i++) {
            if (i < liquidity.length) {
                assertEq(Tick.unwrap(queried[i].tick), Tick.unwrap(liquidity[i].tick));
                assertEq(queried[i].depth, liquidity[i].depth);
            } else {
                assertEq(Tick.unwrap(queried[i].tick), 0);
                assertEq(queried[i].depth, 0);
            }
        }
    }
}
