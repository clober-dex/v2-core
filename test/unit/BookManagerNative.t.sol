// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import "../../src/BookManager.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/libraries/TickBitmap.sol";
import "../routers/MakeRouter.sol";
import "../routers/TakeRouter.sol";
import "../routers/OpenRouter.sol";
import "../routers/ClaimRouter.sol";
import "../routers/CancelRouter.sol";

// @dev Test without fee.
contract BookManagerNativeTest is Test {
    using BookIdLibrary for IBookManager.BookKey;
    using OrderIdLibrary for OrderId;
    using TickLibrary for Tick;
    using FeePolicyLibrary for FeePolicy;

    address public constant DEFAULT_PROVIDER = address(0x1312);
    int24 private constant _MAX_FEE_RATE = 10 ** 6 / 2;
    int24 private constant _MIN_FEE_RATE = -(10 ** 6 / 2);

    BookManager public bookManager;

    IBookManager.BookKey public nativeQuoteKey;
    IBookManager.BookKey public nativeBaseKey;
    IBookManager.BookKey public unopenedKey;

    MockERC20 public mockErc20;
    OpenRouter public openRouter;
    MakeRouter public makeRouter;
    TakeRouter public takeRouter;
    ClaimRouter public claimRouter;
    CancelRouter public cancelRouter;

    receive() external payable {}

    function setUp() public {
        bookManager = new BookManager(address(this), DEFAULT_PROVIDER, "URI", "URI", "name", "SYMBOL");

        mockErc20 = new MockERC20("Mock", "MOCK", 18);

        nativeQuoteKey = IBookManager.BookKey({
            base: Currency.wrap(address(mockErc20)),
            unitSize: 1e12,
            quote: CurrencyLibrary.NATIVE,
            makerPolicy: FeePolicyLibrary.encode(false, 0),
            takerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: IHooks(address(0))
        });

        nativeBaseKey = IBookManager.BookKey({
            base: CurrencyLibrary.NATIVE,
            unitSize: 1e14,
            quote: Currency.wrap(address(mockErc20)),
            makerPolicy: FeePolicyLibrary.encode(false, 0),
            takerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: IHooks(address(0))
        });

        unopenedKey = IBookManager.BookKey({
            base: CurrencyLibrary.NATIVE,
            unitSize: 1e12,
            quote: Currency.wrap(address(mockErc20)),
            makerPolicy: FeePolicyLibrary.encode(true, 0),
            takerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: IHooks(address(0))
        });

        openRouter = new OpenRouter(bookManager);
        makeRouter = new MakeRouter(bookManager);
        takeRouter = new TakeRouter(bookManager);
        claimRouter = new ClaimRouter(bookManager);
        cancelRouter = new CancelRouter(bookManager);

        openRouter.open(nativeQuoteKey, "");
        openRouter.open(nativeBaseKey, "");

        vm.deal(address(this), 100 ether);
        mockErc20.mint(address(this), 100 ether);
        mockErc20.approve(address(makeRouter), type(uint256).max);
        mockErc20.approve(address(takeRouter), type(uint256).max);
    }

    function testOpen() public {
        BookId bookId = unopenedKey.toId();
        vm.expectEmit(address(bookManager));
        emit IBookManager.Open(
            bookId,
            unopenedKey.base,
            unopenedKey.quote,
            unopenedKey.unitSize,
            unopenedKey.makerPolicy,
            unopenedKey.takerPolicy,
            unopenedKey.hooks
        );
        openRouter.open(unopenedKey, "");

        IBookManager.BookKey memory remoteBookKey = bookManager.getBookKey(bookId);

        assertEq(Currency.unwrap(remoteBookKey.base), Currency.unwrap(unopenedKey.base));
        assertEq(Currency.unwrap(remoteBookKey.quote), Currency.unwrap(unopenedKey.quote));
        assertEq(remoteBookKey.unitSize, unopenedKey.unitSize);
        assertEq(remoteBookKey.makerPolicy.rate(), unopenedKey.makerPolicy.rate());
        assertEq(remoteBookKey.makerPolicy.usesQuote(), unopenedKey.makerPolicy.usesQuote());
        assertEq(remoteBookKey.takerPolicy.rate(), unopenedKey.takerPolicy.rate());
        assertEq(remoteBookKey.takerPolicy.usesQuote(), unopenedKey.takerPolicy.usesQuote());
        assertEq(address(remoteBookKey.hooks), address(unopenedKey.hooks));
    }

    function testOpenWithInvalidUnitSize() public {
        unopenedKey.unitSize = 0;

        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidUnitSize.selector));
        openRouter.open(unopenedKey, "");
    }

    function testOpenWithInvalidFeePolicyBoundary() public {
        IBookManager.BookKey memory copiedKey = unopenedKey;
        copiedKey.makerPolicy = FeePolicy.wrap(
            FeePolicy.unwrap(FeePolicyLibrary.encode(copiedKey.makerPolicy.usesQuote(), _MIN_FEE_RATE)) - 1
        );
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidFeePolicy.selector));
        openRouter.open(copiedKey, "");

        copiedKey = unopenedKey;
        copiedKey.makerPolicy = FeePolicy.wrap(
            FeePolicy.unwrap(FeePolicyLibrary.encode(copiedKey.makerPolicy.usesQuote(), _MAX_FEE_RATE)) + 1
        );
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidFeePolicy.selector));
        openRouter.open(copiedKey, "");

        copiedKey = unopenedKey;
        copiedKey.takerPolicy = FeePolicy.wrap(
            FeePolicy.unwrap(FeePolicyLibrary.encode(copiedKey.takerPolicy.usesQuote(), _MIN_FEE_RATE)) - 1
        );
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidFeePolicy.selector));
        openRouter.open(copiedKey, "");

        copiedKey = unopenedKey;
        copiedKey.takerPolicy = FeePolicy.wrap(
            FeePolicy.unwrap(FeePolicyLibrary.encode(copiedKey.takerPolicy.usesQuote(), _MAX_FEE_RATE)) + 1
        );
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidFeePolicy.selector));
        openRouter.open(copiedKey, "");
    }

    function testOpenWithInvalidFeePolicyTotalNegative(int24 makerRate, int24 takerRate) public {
        vm.assume(
            _MIN_FEE_RATE <= makerRate && makerRate <= _MAX_FEE_RATE && _MIN_FEE_RATE <= takerRate
                && takerRate <= _MAX_FEE_RATE && makerRate + takerRate < 0
        );

        IBookManager.BookKey memory copiedKey = unopenedKey;
        copiedKey.makerPolicy = FeePolicyLibrary.encode(copiedKey.makerPolicy.usesQuote(), makerRate);
        copiedKey.takerPolicy = FeePolicyLibrary.encode(copiedKey.takerPolicy.usesQuote(), takerRate);
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidFeePolicy.selector));
        openRouter.open(copiedKey, "");
    }

    function testOpenWithInvalidFeePolicyUnmatchedUseOutputWithNegativeRate() public {
        IBookManager.BookKey memory copiedKey = unopenedKey;
        copiedKey.makerPolicy = FeePolicyLibrary.encode(false, -1);
        copiedKey.takerPolicy = FeePolicyLibrary.encode(true, 2);
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidFeePolicy.selector));
        openRouter.open(copiedKey, "");

        copiedKey = unopenedKey;
        copiedKey.makerPolicy = FeePolicyLibrary.encode(true, -1);
        copiedKey.takerPolicy = FeePolicyLibrary.encode(false, 2);
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidFeePolicy.selector));
        openRouter.open(copiedKey, "");

        copiedKey = unopenedKey;
        copiedKey.makerPolicy = FeePolicyLibrary.encode(false, 2);
        copiedKey.takerPolicy = FeePolicyLibrary.encode(true, -1);
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidFeePolicy.selector));
        openRouter.open(copiedKey, "");

        copiedKey = unopenedKey;
        copiedKey.makerPolicy = FeePolicyLibrary.encode(true, 2);
        copiedKey.takerPolicy = FeePolicyLibrary.encode(false, -1);
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidFeePolicy.selector));
        openRouter.open(copiedKey, "");
    }

    function testOpenWithDuplicatedKey() public {
        vm.expectRevert(abi.encodeWithSelector(Book.BookAlreadyOpened.selector));
        openRouter.open(nativeQuoteKey, "");
    }

    function testMakeERC20Quote() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        uint256 beforeQuoteAmount = mockErc20.balanceOf(address(this));

        vm.expectEmit(address(bookManager));
        emit IBookManager.Make(nativeBaseKey.toId(), address(makeRouter), tick, 0, makeUnit, address(0));
        (OrderId id, uint256 actualQuoteAmount) = makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );
        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(OrderId.unwrap(OrderIdLibrary.encode(nativeBaseKey.toId(), tick, 0)), OrderId.unwrap(id), "RETURN_ID");
        assertEq(actualQuoteAmount, makeUnit * nativeBaseKey.unitSize, "RETURN_QUOTE_AMOUNT");
        assertEq(mockErc20.balanceOf(address(this)), beforeQuoteAmount - actualQuoteAmount, "QUOTE_BALANCE");
        assertEq(bookManager.balanceOf(address(this)), 1, "BOOK_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
        assertEq(bookManager.reservesOf(nativeBaseKey.quote), actualQuoteAmount, "RESERVES");
        assertEq(bookManager.getDepth(nativeBaseKey.toId(), tick), makeUnit, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getHighest(nativeBaseKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeBaseKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeUnit, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
    }

    function testMakeNativeQuote() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        uint256 beforeQuoteAmount = address(this).balance;

        vm.expectEmit(address(bookManager));
        emit IBookManager.Make(nativeQuoteKey.toId(), address(makeRouter), tick, 0, makeUnit, address(0));
        (OrderId id, uint256 actualQuoteAmount) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );
        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(OrderId.unwrap(OrderIdLibrary.encode(nativeQuoteKey.toId(), tick, 0)), OrderId.unwrap(id), "RETURN_ID");
        assertEq(actualQuoteAmount, makeUnit * nativeQuoteKey.unitSize, "RETURN_QUOTE_AMOUNT");
        assertEq(address(this).balance, beforeQuoteAmount - actualQuoteAmount, "QUOTE_BALANCE");
        assertEq(bookManager.balanceOf(address(this)), 1, "BOOK_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
        assertEq(bookManager.reservesOf(nativeQuoteKey.quote), actualQuoteAmount, "RESERVES");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), makeUnit, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getHighest(nativeQuoteKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeUnit, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
    }

    function testMakeWithInvalidProvider() public {
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidProvider.selector, (address(1))));
        makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: Tick.wrap(0), unit: 10000, provider: address(1)}), ""
        );

        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidProvider.selector, (DEFAULT_PROVIDER)));
        makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: Tick.wrap(0), unit: 10000, provider: DEFAULT_PROVIDER}),
            ""
        );
    }

    function testMakeWithInvalidTick() public {
        vm.expectRevert(abi.encodeWithSelector(TickLibrary.InvalidTick.selector));
        makeRouter.make(
            IBookManager.MakeParams({
                key: nativeBaseKey,
                tick: Tick.wrap(TickLibrary.MAX_TICK + 1),
                unit: 10000,
                provider: address(0)
            }),
            ""
        );

        vm.expectRevert(abi.encodeWithSelector(TickLibrary.InvalidTick.selector));
        makeRouter.make(
            IBookManager.MakeParams({
                key: nativeBaseKey,
                tick: Tick.wrap(TickLibrary.MIN_TICK - 1),
                unit: 10000,
                provider: address(0)
            }),
            ""
        );
    }

    function testMakeWithInvalidBookKey() public {
        vm.expectRevert(abi.encodeWithSelector(Book.BookNotOpened.selector));
        makeRouter.make(
            IBookManager.MakeParams({key: unopenedKey, tick: Tick.wrap(0), unit: 10000, provider: address(0)}), ""
        );
    }

    function testTakeNativeQuote() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));

        uint64 takeUnit = 1000;

        vm.expectEmit(address(bookManager));
        emit IBookManager.Take(nativeQuoteKey.toId(), address(takeRouter), tick, takeUnit);
        (uint256 actualQuoteAmount, uint256 actualBaseAmount) = takeRouter.take(
            IBookManager.TakeParams({
                key: nativeQuoteKey,
                tick: bookManager.getHighest(nativeQuoteKey.toId()),
                maxUnit: takeUnit
            }),
            ""
        );

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(actualQuoteAmount, takeUnit * nativeQuoteKey.unitSize, "RETURN_QUOTE_AMOUNT");
        assertEq(
            actualBaseAmount, tick.quoteToBase(uint256(takeUnit) * nativeQuoteKey.unitSize, true), "RETURN_BASE_AMOUNT"
        );
        assertEq(address(this).balance, beforeQuoteAmount + actualQuoteAmount, "QUOTE_BALANCE");
        assertEq(mockErc20.balanceOf(address(this)), beforeBaseAmount - actualBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.quote),
            makeUnit * nativeQuoteKey.unitSize - actualQuoteAmount,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.base), actualBaseAmount, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), makeUnit - takeUnit, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getHighest(nativeQuoteKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeUnit - takeUnit, "ORDER_OPEN");
        assertEq(orderInfo.claimable, takeUnit, "ORDER_CLAIMABLE");
    }

    function testTakeNativeBase() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        uint256 beforeQuoteAmount = mockErc20.balanceOf(address(this));
        uint256 beforeBaseAmount = address(this).balance;

        uint64 takeUnit = 1000;

        vm.expectEmit(address(bookManager));
        emit IBookManager.Take(nativeBaseKey.toId(), address(takeRouter), tick, takeUnit);
        (uint256 actualQuoteAmount, uint256 actualBaseAmount) = takeRouter.take{value: 10 ether}(
            IBookManager.TakeParams({key: nativeBaseKey, tick: tick, maxUnit: takeUnit}), ""
        );

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(actualQuoteAmount, takeUnit * nativeBaseKey.unitSize, "RETURN_QUOTE_AMOUNT");
        assertEq(
            actualBaseAmount, tick.quoteToBase(uint256(takeUnit) * nativeBaseKey.unitSize, true), "RETURN_BASE_AMOUNT"
        );
        assertEq(mockErc20.balanceOf(address(this)), beforeQuoteAmount + actualQuoteAmount, "QUOTE_BALANCE");
        assertEq(address(this).balance, beforeBaseAmount - actualBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeBaseKey.quote),
            makeUnit * nativeBaseKey.unitSize - actualQuoteAmount,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeBaseKey.base), actualBaseAmount, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeBaseKey.toId(), tick), makeUnit - takeUnit, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getHighest(nativeBaseKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeBaseKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeUnit - takeUnit, "ORDER_OPEN");
        assertEq(orderInfo.claimable, takeUnit, "ORDER_CLAIMABLE");
    }

    function testTakeWithInvalidBookKey() public {
        vm.expectRevert(abi.encodeWithSelector(Book.BookNotOpened.selector));
        takeRouter.take(IBookManager.TakeParams({key: unopenedKey, tick: Tick.wrap(0), maxUnit: 1000}), "");
    }

    function testCancelERC20Quote() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeBaseKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        uint64 cancelAmount = 1000;
        uint256 beforeQuoteAmount = mockErc20.balanceOf(address(this));
        uint256 beforeBaseAmount = address(this).balance;

        bookManager.approve(address(cancelRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Cancel(id, cancelAmount);
        cancelRouter.cancel(IBookManager.CancelParams({id: id, toUnit: makeUnit - cancelAmount}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(
            mockErc20.balanceOf(address(this)),
            beforeQuoteAmount + cancelAmount * nativeBaseKey.unitSize,
            "QUOTE_BALANCE"
        );
        assertEq(address(this).balance, beforeBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeBaseKey.quote),
            (makeUnit - cancelAmount) * nativeBaseKey.unitSize,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeBaseKey.base), 0, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeBaseKey.toId(), tick), makeUnit - cancelAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getHighest(nativeBaseKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeBaseKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeUnit - cancelAmount, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testCancelNativeQuote() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        uint64 cancelAmount = 1000;
        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));

        bookManager.approve(address(cancelRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Cancel(id, cancelAmount);
        cancelRouter.cancel(IBookManager.CancelParams({id: id, toUnit: makeUnit - cancelAmount}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(address(this).balance, beforeQuoteAmount + cancelAmount * nativeQuoteKey.unitSize, "QUOTE_BALANCE");
        assertEq(mockErc20.balanceOf(address(this)), beforeBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.quote),
            (makeUnit - cancelAmount) * nativeQuoteKey.unitSize,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.base), 0, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), makeUnit - cancelAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getHighest(nativeQuoteKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeUnit - cancelAmount, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testCancelToZeroWithPartiallyTakenOrder() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        uint64 takeUnit = 1000;
        takeRouter.take{value: 10 ether}(
            IBookManager.TakeParams({
                key: nativeQuoteKey,
                tick: bookManager.getHighest(nativeQuoteKey.toId()),
                maxUnit: takeUnit
            }),
            ""
        );

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeQuoteKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeQuoteKey.base);

        bookManager.approve(address(cancelRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Cancel(id, makeUnit - takeUnit);
        cancelRouter.cancel(IBookManager.CancelParams({id: id, toUnit: 0}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(
            address(this).balance, beforeQuoteAmount + (makeUnit - takeUnit) * nativeQuoteKey.unitSize, "QUOTE_BALANCE"
        );
        assertEq(mockErc20.balanceOf(address(this)), beforeBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.quote),
            beforeQuoteReserve - (makeUnit - takeUnit) * nativeQuoteKey.unitSize,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.base), beforeBaseReserve, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), 0, "DEPTH");
        vm.expectRevert(abi.encodeWithSelector(TickBitmap.EmptyError.selector));
        bookManager.getHighest(nativeQuoteKey.toId());
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), true, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, 0, "ORDER_OPEN");
        assertEq(orderInfo.claimable, takeUnit, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testCancelToZeroShouldBurnWithZeroClaimable() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeQuoteKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeQuoteKey.base);

        bookManager.approve(address(cancelRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Cancel(id, makeUnit);
        cancelRouter.cancel(IBookManager.CancelParams({id: id, toUnit: 0}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(address(this).balance, beforeQuoteAmount + makeUnit * nativeQuoteKey.unitSize, "QUOTE_BALANCE");
        assertEq(mockErc20.balanceOf(address(this)), beforeBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.quote),
            beforeQuoteReserve - makeUnit * nativeQuoteKey.unitSize,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.base), beforeBaseReserve, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), 0, "DEPTH");
        vm.expectRevert(abi.encodeWithSelector(TickBitmap.EmptyError.selector));
        bookManager.getHighest(nativeQuoteKey.toId());
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), true, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, 0, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 0, "ORDER_BALANCE");
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, (OrderId.unwrap(id))));
        bookManager.ownerOf(OrderId.unwrap(id));
    }

    function testCancelNonexistentOrder() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, (123)));
        cancelRouter.cancel(IBookManager.CancelParams({id: OrderId.wrap(123), toUnit: 0}), "");
    }

    function testCancelAuth() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721InsufficientApproval.selector, address(cancelRouter), OrderId.unwrap(id)
            )
        );
        cancelRouter.cancel(IBookManager.CancelParams({id: id, toUnit: 0}), "");
    }

    function testClaimERC20Base() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        uint64 takeUnit = 1000;
        takeRouter.take(
            IBookManager.TakeParams({
                key: nativeQuoteKey,
                tick: bookManager.getHighest(nativeQuoteKey.toId()),
                maxUnit: takeUnit
            }),
            ""
        );

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeQuoteKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeQuoteKey.base);
        IBookManager.OrderInfo memory beforeOrderInfo = bookManager.getOrder(id);

        bookManager.approve(address(claimRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Claim(id, takeUnit);
        claimRouter.claim(id, "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(address(this).balance, beforeQuoteAmount, "QUOTE_BALANCE");
        assertEq(
            mockErc20.balanceOf(address(this)),
            beforeBaseAmount + tick.quoteToBase(uint256(takeUnit) * nativeQuoteKey.unitSize, false),
            "BASE_BALANCE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.quote), beforeQuoteReserve, "RESERVES_QUOTE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.base),
            beforeBaseReserve - tick.quoteToBase(uint256(takeUnit) * nativeQuoteKey.unitSize, false),
            "RESERVES_BASE"
        );
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), makeUnit - takeUnit, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getHighest(nativeQuoteKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.open, beforeOrderInfo.open, "ORDER_OPEN");
        assertEq(orderInfo.claimable, beforeOrderInfo.claimable - takeUnit, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testClaimNativeBase() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        uint64 takeUnit = 1000;
        takeRouter.take{value: 10 ether}(
            IBookManager.TakeParams({key: nativeBaseKey, tick: tick, maxUnit: takeUnit}), ""
        );

        uint256 beforeQuoteAmount = mockErc20.balanceOf(address(this));
        uint256 beforeBaseAmount = address(this).balance;
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeBaseKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeBaseKey.base);
        IBookManager.OrderInfo memory beforeOrderInfo = bookManager.getOrder(id);

        bookManager.approve(address(claimRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Claim(id, takeUnit);
        claimRouter.claim(id, "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(mockErc20.balanceOf(address(this)), beforeQuoteAmount, "QUOTE_BALANCE");
        assertEq(
            address(this).balance,
            beforeBaseAmount + tick.quoteToBase(uint256(takeUnit) * nativeBaseKey.unitSize, false),
            "BASE_BALANCE"
        );
        assertEq(bookManager.reservesOf(nativeBaseKey.quote), beforeQuoteReserve, "RESERVES_QUOTE");
        assertEq(
            bookManager.reservesOf(nativeBaseKey.base),
            beforeBaseReserve - tick.quoteToBase(uint256(takeUnit) * nativeBaseKey.unitSize, false),
            "RESERVES_BASE"
        );
        assertEq(bookManager.getDepth(nativeBaseKey.toId(), tick), makeUnit - takeUnit, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getHighest(nativeBaseKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeBaseKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.open, beforeOrderInfo.open, "ORDER_OPEN");
        assertEq(orderInfo.claimable, beforeOrderInfo.claimable - takeUnit, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testClaimShouldBurnWithZeroPendingOrder() public {
        uint64 makeUnit = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, unit: makeUnit, provider: address(0)}), ""
        );

        takeRouter.take(
            IBookManager.TakeParams({
                key: nativeQuoteKey,
                tick: bookManager.getHighest(nativeQuoteKey.toId()),
                maxUnit: makeUnit
            }),
            ""
        );

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeQuoteKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeQuoteKey.base);

        bookManager.approve(address(claimRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Claim(id, makeUnit);
        claimRouter.claim(id, "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(address(this).balance, beforeQuoteAmount, "QUOTE_BALANCE");
        assertEq(
            mockErc20.balanceOf(address(this)),
            beforeBaseAmount + tick.quoteToBase(uint256(makeUnit) * nativeQuoteKey.unitSize, false),
            "BASE_BALANCE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.quote), beforeQuoteReserve, "RESERVES_QUOTE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.base),
            beforeBaseReserve - tick.quoteToBase(uint256(makeUnit) * nativeQuoteKey.unitSize, false),
            "RESERVES_BASE"
        );
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), 0, "DEPTH");
        vm.expectRevert(abi.encodeWithSelector(TickBitmap.EmptyError.selector));
        bookManager.getHighest(nativeQuoteKey.toId());
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), true, "IS_EMPTY");
        assertEq(orderInfo.open, 0, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 0, "ORDER_BALANCE");
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, (OrderId.unwrap(id))));
        bookManager.ownerOf(OrderId.unwrap(id));
    }

    function testClaimNonexistentOrder() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, (123)));
        claimRouter.claim(OrderId.wrap(123), "");
    }
}
