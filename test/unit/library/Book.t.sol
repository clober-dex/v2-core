// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../src/interfaces/IHooks.sol";
import "../../../src/libraries/Currency.sol";
import "../../../src/libraries/FeePolicy.sol";
import "../../mocks/BookWrapper.sol";

contract BookTest is Test {
    using FeePolicyLibrary for FeePolicy;
    using CurrencyLibrary for Currency;

    BookId public constant BOOK_ID = BookId.wrap(123);
    BookWrapper public book;
    IBookManager.BookKey public key;

    function setUp() public {
        book = new BookWrapper(BOOK_ID);

        key = IBookManager.BookKey({
            base: CurrencyLibrary.NATIVE,
            unitSize: 1e12,
            quote: Currency.wrap(address(123)),
            makerPolicy: FeePolicyLibrary.encode(false, 0),
            takerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: IHooks(address(0))
        });
    }

    function testOpen() public {
        assertFalse(book.isOpened());
        vm.expectRevert(abi.encodeWithSelector(Book.BookNotOpened.selector));
        book.checkOpened();

        book.open(key);
        assertTrue(book.isOpened());
        book.checkOpened();
        IBookManager.BookKey memory actualKey = book.getBookKey();
        assertEq(Currency.unwrap(actualKey.base), Currency.unwrap(key.base));
        assertEq(actualKey.unitSize, key.unitSize);
        assertEq(Currency.unwrap(actualKey.quote), Currency.unwrap(key.quote));
        assertEq(actualKey.makerPolicy.rate(), key.makerPolicy.rate());
        assertEq(actualKey.makerPolicy.usesQuote(), key.makerPolicy.usesQuote());
        assertEq(actualKey.takerPolicy.rate(), key.takerPolicy.rate());
        assertEq(actualKey.takerPolicy.usesQuote(), key.takerPolicy.usesQuote());
        assertEq(address(actualKey.hooks), address(key.hooks));

        assertTrue(book.isEmpty());

        vm.expectRevert(abi.encodeWithSelector(TickBitmap.EmptyError.selector));
        book.getHighest();
    }

    function testOpenDuplicatedKey() public {
        book.open(key);
        vm.expectRevert(abi.encodeWithSelector(Book.BookAlreadyOpened.selector));
        book.open(key);
    }

    modifier opened() {
        book.open(key);
        _;
    }

    function testMake() public opened {
        assertTrue(book.isEmpty());

        uint40 index = book.make(Tick.wrap(0), 100);
        assertFalse(book.isEmpty());
        assertEq(Tick.unwrap(book.getHighest()), 0);
        assertEq(index, 0);
        assertEq(book.depth(Tick.wrap(0)), 100);

        index = book.make(Tick.wrap(0), 200);
        assertFalse(book.isEmpty());
        assertEq(Tick.unwrap(book.getHighest()), 0);
        assertEq(index, 1);
        assertEq(book.depth(Tick.wrap(0)), 300);
    }

    function testMakeWhenStaleOrderExists() public opened {
        uint40 index = book.make(Tick.wrap(0), 100);
        assertEq(index, 0);
        assertEq(book.depth(Tick.wrap(0)), 100);

        book.setQueueIndex(Tick.wrap(0), Book.MAX_ORDER);

        vm.expectRevert(abi.encodeWithSelector(Book.QueueReplaceFailed.selector));
        book.make(Tick.wrap(0), 200);
    }

    function testMakeWhenClaimableStaleOrderExists() public opened {
        uint40 index = book.make(Tick.wrap(0), 100);
        index = book.make(Tick.wrap(0), 200);

        book.setQueueIndex(Tick.wrap(0), Book.MAX_ORDER);

        book.take(Tick.wrap(0), 150);

        index = book.make(Tick.wrap(0), 1000);
        assertEq(index, Book.MAX_ORDER);
        assertEq(book.depth(Tick.wrap(0)), 1150);

        vm.expectRevert(abi.encodeWithSelector(Book.QueueReplaceFailed.selector));
        book.make(Tick.wrap(0), 200);
    }

    function testMakeWithZeroUnit() public opened {
        vm.expectRevert(abi.encodeWithSelector(Book.ZeroUnit.selector));
        book.make(Tick.wrap(0), 0);
    }

    function testTake() public opened {
        book.make(Tick.wrap(0), 100);
        book.make(Tick.wrap(0), 200);
        book.make(Tick.wrap(0), 300);
        book.make(Tick.wrap(0), 400);
        book.make(Tick.wrap(0), 500);

        uint64 unit = book.take(Tick.wrap(0), 150);
        assertEq(unit, 150);
        assertEq(book.depth(Tick.wrap(0)), 1350);

        unit = book.take(Tick.wrap(0), 1000);
        assertEq(unit, 1000);
        assertEq(book.depth(Tick.wrap(0)), 350);

        unit = book.take(Tick.wrap(0), 1000);
        assertEq(unit, 350);
        assertEq(book.depth(Tick.wrap(0)), 0);
    }

    function testTakeAndCleanTickBitmap() public opened {
        book.make(Tick.wrap(0), 100);
        book.make(Tick.wrap(4), 200);

        book.take(Tick.wrap(0), 200);

        assertEq(Tick.unwrap(book.getHighest()), 4);
    }

    function testCancel() public opened {
        uint40 index = book.make(Tick.wrap(0), 100);
        assertEq(index, 0);
        assertEq(book.depth(Tick.wrap(0)), 100);

        index = book.make(Tick.wrap(0), 200);
        assertEq(index, 1);
        assertEq(book.depth(Tick.wrap(0)), 300);

        book.take(Tick.wrap(0), 30);
        assertEq(book.depth(Tick.wrap(0)), 270);

        (uint64 canceledUnit, uint64 pendingUnit) = book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0), 40);
        assertEq(canceledUnit, 30);
        assertEq(book.depth(Tick.wrap(0)), 240);
        assertEq(pendingUnit, 70);

        (canceledUnit, pendingUnit) = book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1), 150);
        assertEq(canceledUnit, 50);
        assertEq(book.depth(Tick.wrap(0)), 190);
        assertEq(pendingUnit, 150);

        (canceledUnit, pendingUnit) = book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1), 0);
        assertEq(canceledUnit, 150);
        assertEq(book.depth(Tick.wrap(0)), 40);
        assertEq(pendingUnit, 0);
    }

    function testCancelToTooLargeAmount() public opened {
        uint40 index = book.make(Tick.wrap(0), 100);
        assertEq(index, 0);
        assertEq(book.depth(Tick.wrap(0)), 100);

        index = book.make(Tick.wrap(0), 200);
        assertEq(index, 1);
        assertEq(book.depth(Tick.wrap(0)), 300);

        book.take(Tick.wrap(0), 30);
        assertEq(book.depth(Tick.wrap(0)), 270);

        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)).pending, 100);
        vm.expectRevert(abi.encodeWithSelector(Book.CancelFailed.selector, (70)));
        book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0), 71);
    }

    function testCancelAndRemove() public opened {
        book.make(Tick.wrap(0), 100);
        book.make(Tick.wrap(123), 100);
        book.make(Tick.wrap(1234), 100);

        assertEq(Tick.unwrap(book.getHighest()), 1234);

        book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(1234), 0), 0);

        assertEq(Tick.unwrap(book.getHighest()), 123);

        book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0), 0);

        assertFalse(book.tickBitmapHas(Tick.wrap(0)));
    }

    function testClaim() public opened {
        book.make(Tick.wrap(0), 100);
        book.make(Tick.wrap(0), 200);
        book.make(Tick.wrap(0), 300);

        book.take(Tick.wrap(0), 150);

        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)).pending, 100);
        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1)).pending, 200);
        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 2)).pending, 300);
        assertEq(book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)), 100);
        assertEq(book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1)), 50);
        assertEq(book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 2)), 0);

        uint64 claimedUnit = book.claim(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0));
        assertEq(claimedUnit, 100);
        claimedUnit = book.claim(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1));
        assertEq(claimedUnit, 50);
        claimedUnit = book.claim(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 2));
        assertEq(claimedUnit, 0);

        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)).pending, 0);
        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1)).pending, 150);
        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 2)).pending, 300);
    }

    function testCalculateClaimableUnit() public opened {
        book.make(Tick.wrap(0), 100); // index 0
        book.make(Tick.wrap(0), 200); // index 1
        book.make(Tick.wrap(0), 300); // index 2

        book.take(Tick.wrap(0), 150);

        assertEq(book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)), 100);
        assertEq(book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1)), 50);
        assertEq(book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 2)), 0);
    }

    function testCalculateClaimableUnitWithStaleOrder() public opened {
        book.make(Tick.wrap(0), 100); // index 0
        book.make(Tick.wrap(0), 200); // index 1
        book.make(Tick.wrap(0), 300); // index 2

        book.take(Tick.wrap(0), 150);

        book.setQueueIndex(Tick.wrap(0), Book.MAX_ORDER + 4);

        // @dev Book logic always considers as claimable.
        assertEq(book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)), 100);
        assertEq(book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1)), 200);
        assertEq(book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 2)), 300);
    }

    function testCalculateClaimableUnitNotOverflow() public opened {
        book.make(Tick.wrap(0), type(uint64).max - 1);
        book.take(Tick.wrap(0), type(uint64).max - 1);
        book.calculateClaimableUnit(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0));
    }
}
