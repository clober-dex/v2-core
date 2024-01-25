// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../../contracts/interfaces/IHooks.sol";
import "../../../../contracts/libraries/Currency.sol";

import "../../mocks/BookWrapper.sol";

contract BookTest is Test {
    using CurrencyLibrary for Currency;

    BookId public constant BOOK_ID = BookId.wrap(123);
    BookWrapper public book;
    IBookManager.BookKey public key;

    function setUp() public {
        book = new BookWrapper(BOOK_ID);

        key = IBookManager.BookKey({
            base: CurrencyLibrary.NATIVE,
            unit: 1e12,
            quote: Currency.wrap(address(123)),
            makerPolicy: IBookManager.FeePolicy({rate: 0, useOutput: true}),
            takerPolicy: IBookManager.FeePolicy({rate: 0, useOutput: true}),
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
        assertEq(actualKey.unit, key.unit);
        assertEq(Currency.unwrap(actualKey.quote), Currency.unwrap(key.quote));
        assertEq(actualKey.makerPolicy.rate, key.makerPolicy.rate);
        assertEq(actualKey.makerPolicy.useOutput, key.makerPolicy.useOutput);
        assertEq(actualKey.takerPolicy.rate, key.takerPolicy.rate);
        assertEq(actualKey.takerPolicy.useOutput, key.takerPolicy.useOutput);
        assertEq(address(actualKey.hooks), address(key.hooks));
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
        uint40 index = book.make(Tick.wrap(0), 100);
        assertEq(index, 0);
        assertEq(book.depth(Tick.wrap(0)), 100);

        index = book.make(Tick.wrap(0), 200);
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

        book.take(150);

        index = book.make(Tick.wrap(0), 1000);
        assertEq(index, Book.MAX_ORDER);
        assertEq(book.depth(Tick.wrap(0)), 1150);

        vm.expectRevert(abi.encodeWithSelector(Book.QueueReplaceFailed.selector));
        book.make(Tick.wrap(0), 200);
    }

    function testTake() public opened {
        book.make(Tick.wrap(0), 100);
        book.make(Tick.wrap(0), 200);
        book.make(Tick.wrap(0), 300);
        book.make(Tick.wrap(0), 400);
        book.make(Tick.wrap(0), 500);

        (Tick tick, uint64 amount) = book.take(150);
        assertEq(Tick.unwrap(tick), 0);
        assertEq(amount, 150);
        assertEq(book.depth(Tick.wrap(0)), 1350);

        (tick, amount) = book.take(1000);
        assertEq(Tick.unwrap(tick), 0);
        assertEq(amount, 1000);
        assertEq(book.depth(Tick.wrap(0)), 350);

        (tick, amount) = book.take(1000);
        assertEq(Tick.unwrap(tick), 0);
        assertEq(amount, 350);
        assertEq(book.depth(Tick.wrap(0)), 0);
    }

    function testTakeAndCleanHeap() public opened {
        book.make(Tick.wrap(0), 100);
        book.make(Tick.wrap(4), 200);

        book.take(200);

        assertEq(Tick.unwrap(book.getRoot()), 4);
    }

    function testCancel() public opened {
        uint40 index = book.make(Tick.wrap(0), 100);
        assertEq(index, 0);
        assertEq(book.depth(Tick.wrap(0)), 100);

        index = book.make(Tick.wrap(0), 200);
        assertEq(index, 1);
        assertEq(book.depth(Tick.wrap(0)), 300);

        book.take(30);
        assertEq(book.depth(Tick.wrap(0)), 270);

        uint64 canceledAmount = book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0), 40);
        assertEq(canceledAmount, 30);
        assertEq(book.depth(Tick.wrap(0)), 240);
        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)).pending, 70);

        canceledAmount = book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1), 150);
        assertEq(canceledAmount, 50);
        assertEq(book.depth(Tick.wrap(0)), 190);
        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1)).pending, 150);

        canceledAmount = book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1), 0);
        assertEq(canceledAmount, 150);
        assertEq(book.depth(Tick.wrap(0)), 40);
        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1)).pending, 0);
    }

    function testCancelToTooLargeAmount() public opened {
        uint40 index = book.make(Tick.wrap(0), 100);
        assertEq(index, 0);
        assertEq(book.depth(Tick.wrap(0)), 100);

        index = book.make(Tick.wrap(0), 200);
        assertEq(index, 1);
        assertEq(book.depth(Tick.wrap(0)), 300);

        book.take(30);
        assertEq(book.depth(Tick.wrap(0)), 270);

        assertEq(book.getOrder(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)).pending, 100);
        vm.expectRevert(abi.encodeWithSelector(Book.CancelFailed.selector, (70)));
        book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0), 71);
    }

    function testCancelAndCleanHeap() public opened {
        book.make(Tick.wrap(0), 100);
        book.make(Tick.wrap(123), 100);

        assertEq(Tick.unwrap(book.getRoot()), 0);

        book.cancel(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0), 0);

        assertEq(Tick.unwrap(book.getRoot()), 123);
    }

    function testCalculateClaimableRawAmount() public opened {
        book.make(Tick.wrap(0), 100); // index 0
        book.make(Tick.wrap(0), 200); // index 1
        book.make(Tick.wrap(0), 300); // index 2

        book.take(150);

        assertEq(book.calculateClaimableRawAmount(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)), 100);
        assertEq(book.calculateClaimableRawAmount(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1)), 50);
        assertEq(book.calculateClaimableRawAmount(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 2)), 0);
    }

    function testCalculateClaimableRawAmountWithStaleOrder() public opened {
        book.make(Tick.wrap(0), 100); // index 0
        book.make(Tick.wrap(0), 200); // index 1
        book.make(Tick.wrap(0), 300); // index 2

        book.take(150);

        book.setQueueIndex(Tick.wrap(0), Book.MAX_ORDER + 4);

        // @dev Book logic always considers as claimable.
        assertEq(book.calculateClaimableRawAmount(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 0)), 100);
        assertEq(book.calculateClaimableRawAmount(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 1)), 200);
        assertEq(book.calculateClaimableRawAmount(OrderIdLibrary.encode(BOOK_ID, Tick.wrap(0), 2)), 300);
    }
}
