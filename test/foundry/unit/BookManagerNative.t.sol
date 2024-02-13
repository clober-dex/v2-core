// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import "../../../contracts/BookManager.sol";
import "../mocks/MockERC20.sol";
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
            unit: 1e12,
            quote: CurrencyLibrary.NATIVE,
            makerPolicy: FeePolicyLibrary.encode(false, 0),
            takerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: IHooks(address(0))
        });

        nativeBaseKey = IBookManager.BookKey({
            base: CurrencyLibrary.NATIVE,
            unit: 1e14,
            quote: Currency.wrap(address(mockErc20)),
            makerPolicy: FeePolicyLibrary.encode(false, 0),
            takerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: IHooks(address(0))
        });

        unopenedKey = IBookManager.BookKey({
            base: CurrencyLibrary.NATIVE,
            unit: 1e12,
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
            unopenedKey.unit,
            unopenedKey.makerPolicy,
            unopenedKey.takerPolicy,
            unopenedKey.hooks
        );
        openRouter.open(unopenedKey, "");

        IBookManager.BookKey memory remoteBookKey = bookManager.getBookKey(bookId);

        assertEq(Currency.unwrap(remoteBookKey.base), Currency.unwrap(unopenedKey.base));
        assertEq(Currency.unwrap(remoteBookKey.quote), Currency.unwrap(unopenedKey.quote));
        assertEq(remoteBookKey.unit, unopenedKey.unit);
        assertEq(remoteBookKey.makerPolicy.rate(), unopenedKey.makerPolicy.rate());
        assertEq(remoteBookKey.makerPolicy.usesQuote(), unopenedKey.makerPolicy.usesQuote());
        assertEq(remoteBookKey.takerPolicy.rate(), unopenedKey.takerPolicy.rate());
        assertEq(remoteBookKey.takerPolicy.usesQuote(), unopenedKey.takerPolicy.usesQuote());
        assertEq(address(remoteBookKey.hooks), address(unopenedKey.hooks));
    }

    function testOpenWithInvalidUnit() public {
        unopenedKey.unit = 0;

        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidUnit.selector));
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
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        uint256 beforeQuoteAmount = mockErc20.balanceOf(address(this));

        vm.expectEmit(address(bookManager));
        emit IBookManager.Make(nativeBaseKey.toId(), address(makeRouter), tick, 0, makeAmount);
        (OrderId id, uint256 actualQuoteAmount) = makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );
        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(OrderId.unwrap(OrderIdLibrary.encode(nativeBaseKey.toId(), tick, 0)), OrderId.unwrap(id), "RETURN_ID");
        assertEq(actualQuoteAmount, makeAmount * nativeBaseKey.unit, "RETURN_QUOTE_AMOUNT");
        assertEq(mockErc20.balanceOf(address(this)), beforeQuoteAmount - actualQuoteAmount, "QUOTE_BALANCE");
        assertEq(bookManager.balanceOf(address(this)), 1, "BOOK_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
        assertEq(bookManager.reservesOf(nativeBaseKey.quote), actualQuoteAmount, "RESERVES");
        assertEq(bookManager.getDepth(nativeBaseKey.toId(), tick), makeAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getLowest(nativeBaseKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeBaseKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeAmount, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
    }

    function testMakeNativeQuote() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        uint256 beforeQuoteAmount = address(this).balance;

        vm.expectEmit(address(bookManager));
        emit IBookManager.Make(nativeQuoteKey.toId(), address(makeRouter), tick, 0, makeAmount);
        (OrderId id, uint256 actualQuoteAmount) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );
        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(OrderId.unwrap(OrderIdLibrary.encode(nativeQuoteKey.toId(), tick, 0)), OrderId.unwrap(id), "RETURN_ID");
        assertEq(actualQuoteAmount, makeAmount * nativeQuoteKey.unit, "RETURN_QUOTE_AMOUNT");
        assertEq(address(this).balance, beforeQuoteAmount - actualQuoteAmount, "QUOTE_BALANCE");
        assertEq(bookManager.balanceOf(address(this)), 1, "BOOK_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
        assertEq(bookManager.reservesOf(nativeQuoteKey.quote), actualQuoteAmount, "RESERVES");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), makeAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getLowest(nativeQuoteKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeAmount, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
    }

    function testMakeWithInvalidProvider() public {
        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidProvider.selector, (address(1))));
        makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: Tick.wrap(0), amount: 10000, provider: address(1)}), ""
        );

        vm.expectRevert(abi.encodeWithSelector(IBookManager.InvalidProvider.selector, (DEFAULT_PROVIDER)));
        makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: Tick.wrap(0), amount: 10000, provider: DEFAULT_PROVIDER}),
            ""
        );
    }

    function testMakeWithInvalidTick() public {
        vm.expectRevert(abi.encodeWithSelector(TickLibrary.InvalidTick.selector));
        makeRouter.make(
            IBookManager.MakeParams({
                key: nativeBaseKey,
                tick: Tick.wrap(TickLibrary.MAX_TICK + 1),
                amount: 10000,
                provider: address(0)
            }),
            ""
        );

        vm.expectRevert(abi.encodeWithSelector(TickLibrary.InvalidTick.selector));
        makeRouter.make(
            IBookManager.MakeParams({
                key: nativeBaseKey,
                tick: Tick.wrap(TickLibrary.MIN_TICK - 1),
                amount: 10000,
                provider: address(0)
            }),
            ""
        );
    }

    function testMakeWithInvalidBookKey() public {
        vm.expectRevert(abi.encodeWithSelector(Book.BookNotOpened.selector));
        makeRouter.make(
            IBookManager.MakeParams({key: unopenedKey, tick: Tick.wrap(0), amount: 10000, provider: address(0)}), ""
        );
    }

    function testTakeNativeQuote() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));

        uint64 takeAmount = 1000;

        vm.expectEmit(address(bookManager));
        emit IBookManager.Take(nativeQuoteKey.toId(), address(takeRouter), tick, takeAmount);
        (uint256 actualQuoteAmount, uint256 actualBaseAmount) =
            takeRouter.take(IBookManager.TakeParams({key: nativeQuoteKey, maxAmount: takeAmount}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(actualQuoteAmount, takeAmount * nativeQuoteKey.unit, "RETURN_QUOTE_AMOUNT");
        assertEq(
            actualBaseAmount, tick.quoteToBase(uint256(takeAmount) * nativeQuoteKey.unit, true), "RETURN_BASE_AMOUNT"
        );
        assertEq(address(this).balance, beforeQuoteAmount + actualQuoteAmount, "QUOTE_BALANCE");
        assertEq(mockErc20.balanceOf(address(this)), beforeBaseAmount - actualBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.quote),
            makeAmount * nativeQuoteKey.unit - actualQuoteAmount,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.base), actualBaseAmount, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), makeAmount - takeAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getLowest(nativeQuoteKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeAmount - takeAmount, "ORDER_OPEN");
        assertEq(orderInfo.claimable, takeAmount, "ORDER_CLAIMABLE");
    }

    function testTakeNativeBase() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        uint256 beforeQuoteAmount = mockErc20.balanceOf(address(this));
        uint256 beforeBaseAmount = address(this).balance;

        uint64 takeAmount = 1000;

        vm.expectEmit(address(bookManager));
        emit IBookManager.Take(nativeBaseKey.toId(), address(takeRouter), tick, takeAmount);
        (uint256 actualQuoteAmount, uint256 actualBaseAmount) =
            takeRouter.take{value: 10 ether}(IBookManager.TakeParams({key: nativeBaseKey, maxAmount: takeAmount}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(actualQuoteAmount, takeAmount * nativeBaseKey.unit, "RETURN_QUOTE_AMOUNT");
        assertEq(
            actualBaseAmount, tick.quoteToBase(uint256(takeAmount) * nativeBaseKey.unit, true), "RETURN_BASE_AMOUNT"
        );
        assertEq(mockErc20.balanceOf(address(this)), beforeQuoteAmount + actualQuoteAmount, "QUOTE_BALANCE");
        assertEq(address(this).balance, beforeBaseAmount - actualBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeBaseKey.quote),
            makeAmount * nativeBaseKey.unit - actualQuoteAmount,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeBaseKey.base), actualBaseAmount, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeBaseKey.toId(), tick), makeAmount - takeAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getLowest(nativeBaseKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeBaseKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeAmount - takeAmount, "ORDER_OPEN");
        assertEq(orderInfo.claimable, takeAmount, "ORDER_CLAIMABLE");
    }

    function testTakeWithInvalidBookKey() public {
        vm.expectRevert(abi.encodeWithSelector(Book.BookNotOpened.selector));
        takeRouter.take(IBookManager.TakeParams({key: unopenedKey, maxAmount: 1000}), "");
    }

    function testCancelERC20Quote() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeBaseKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        uint64 cancelAmount = 1000;
        uint256 beforeQuoteAmount = mockErc20.balanceOf(address(this));
        uint256 beforeBaseAmount = address(this).balance;

        bookManager.approve(address(cancelRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Cancel(id, cancelAmount);
        cancelRouter.cancel(IBookManager.CancelParams({id: id, to: makeAmount - cancelAmount}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(
            mockErc20.balanceOf(address(this)), beforeQuoteAmount + cancelAmount * nativeBaseKey.unit, "QUOTE_BALANCE"
        );
        assertEq(address(this).balance, beforeBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeBaseKey.quote),
            (makeAmount - cancelAmount) * nativeBaseKey.unit,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeBaseKey.base), 0, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeBaseKey.toId(), tick), makeAmount - cancelAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getLowest(nativeBaseKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeBaseKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeAmount - cancelAmount, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testCancelNativeQuote() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        uint64 cancelAmount = 1000;
        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));

        bookManager.approve(address(cancelRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Cancel(id, cancelAmount);
        cancelRouter.cancel(IBookManager.CancelParams({id: id, to: makeAmount - cancelAmount}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(address(this).balance, beforeQuoteAmount + cancelAmount * nativeQuoteKey.unit, "QUOTE_BALANCE");
        assertEq(mockErc20.balanceOf(address(this)), beforeBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.quote),
            (makeAmount - cancelAmount) * nativeQuoteKey.unit,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.base), 0, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), makeAmount - cancelAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getLowest(nativeQuoteKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, makeAmount - cancelAmount, "ORDER_OPEN");
        assertEq(orderInfo.claimable, 0, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testCancelToZeroWithPartiallyTakenOrder() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        uint64 takeAmount = 1000;
        takeRouter.take{value: 10 ether}(IBookManager.TakeParams({key: nativeQuoteKey, maxAmount: takeAmount}), "");

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeQuoteKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeQuoteKey.base);

        bookManager.approve(address(cancelRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Cancel(id, makeAmount - takeAmount);
        cancelRouter.cancel(IBookManager.CancelParams({id: id, to: 0}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(
            address(this).balance, beforeQuoteAmount + (makeAmount - takeAmount) * nativeQuoteKey.unit, "QUOTE_BALANCE"
        );
        assertEq(mockErc20.balanceOf(address(this)), beforeBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.quote),
            beforeQuoteReserve - (makeAmount - takeAmount) * nativeQuoteKey.unit,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.base), beforeBaseReserve, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), 0, "DEPTH");
        vm.expectRevert(abi.encodeWithSelector(TickBitmap.EmptyError.selector));
        bookManager.getLowest(nativeQuoteKey.toId());
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), true, "IS_EMPTY");
        assertEq(orderInfo.provider, address(0), "ORDER_PROVIDER");
        assertEq(orderInfo.open, 0, "ORDER_OPEN");
        assertEq(orderInfo.claimable, takeAmount, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testCancelToZeroShouldBurnWithZeroClaimable() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeQuoteKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeQuoteKey.base);

        bookManager.approve(address(cancelRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Cancel(id, makeAmount);
        cancelRouter.cancel(IBookManager.CancelParams({id: id, to: 0}), "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(address(this).balance, beforeQuoteAmount + makeAmount * nativeQuoteKey.unit, "QUOTE_BALANCE");
        assertEq(mockErc20.balanceOf(address(this)), beforeBaseAmount, "BASE_BALANCE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.quote),
            beforeQuoteReserve - makeAmount * nativeQuoteKey.unit,
            "RESERVES_QUOTE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.base), beforeBaseReserve, "RESERVES_BASE");
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), 0, "DEPTH");
        vm.expectRevert(abi.encodeWithSelector(TickBitmap.EmptyError.selector));
        bookManager.getLowest(nativeQuoteKey.toId());
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
        cancelRouter.cancel(IBookManager.CancelParams({id: OrderId.wrap(123), to: 0}), "");
    }

    function testCancelAuth() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721InsufficientApproval.selector, address(cancelRouter), OrderId.unwrap(id)
            )
        );
        cancelRouter.cancel(IBookManager.CancelParams({id: id, to: 0}), "");
    }

    function testClaimERC20Base() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        uint64 takeAmount = 1000;
        takeRouter.take(IBookManager.TakeParams({key: nativeQuoteKey, maxAmount: takeAmount}), "");

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeQuoteKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeQuoteKey.base);
        IBookManager.OrderInfo memory beforeOrderInfo = bookManager.getOrder(id);

        bookManager.approve(address(claimRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Claim(id, takeAmount);
        claimRouter.claim(id, "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(address(this).balance, beforeQuoteAmount, "QUOTE_BALANCE");
        assertEq(
            mockErc20.balanceOf(address(this)),
            beforeBaseAmount + tick.quoteToBase(uint256(takeAmount) * nativeQuoteKey.unit, false),
            "BASE_BALANCE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.quote), beforeQuoteReserve, "RESERVES_QUOTE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.base),
            beforeBaseReserve - tick.quoteToBase(uint256(takeAmount) * nativeQuoteKey.unit, false),
            "RESERVES_BASE"
        );
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), makeAmount - takeAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getLowest(nativeQuoteKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeQuoteKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.open, beforeOrderInfo.open, "ORDER_OPEN");
        assertEq(orderInfo.claimable, beforeOrderInfo.claimable - takeAmount, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testClaimNativeBase() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make(
            IBookManager.MakeParams({key: nativeBaseKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        uint64 takeAmount = 1000;
        takeRouter.take{value: 10 ether}(IBookManager.TakeParams({key: nativeBaseKey, maxAmount: takeAmount}), "");

        uint256 beforeQuoteAmount = mockErc20.balanceOf(address(this));
        uint256 beforeBaseAmount = address(this).balance;
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeBaseKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeBaseKey.base);
        IBookManager.OrderInfo memory beforeOrderInfo = bookManager.getOrder(id);

        bookManager.approve(address(claimRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Claim(id, takeAmount);
        claimRouter.claim(id, "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(mockErc20.balanceOf(address(this)), beforeQuoteAmount, "QUOTE_BALANCE");
        assertEq(
            address(this).balance,
            beforeBaseAmount + tick.quoteToBase(uint256(takeAmount) * nativeBaseKey.unit, false),
            "BASE_BALANCE"
        );
        assertEq(bookManager.reservesOf(nativeBaseKey.quote), beforeQuoteReserve, "RESERVES_QUOTE");
        assertEq(
            bookManager.reservesOf(nativeBaseKey.base),
            beforeBaseReserve - tick.quoteToBase(uint256(takeAmount) * nativeBaseKey.unit, false),
            "RESERVES_BASE"
        );
        assertEq(bookManager.getDepth(nativeBaseKey.toId(), tick), makeAmount - takeAmount, "DEPTH");
        assertEq(Tick.unwrap(bookManager.getLowest(nativeBaseKey.toId())), Tick.unwrap(tick), "LOWEST");
        assertEq(bookManager.isEmpty(nativeBaseKey.toId()), false, "IS_EMPTY");
        assertEq(orderInfo.open, beforeOrderInfo.open, "ORDER_OPEN");
        assertEq(orderInfo.claimable, beforeOrderInfo.claimable - takeAmount, "ORDER_CLAIMABLE");
        assertEq(bookManager.balanceOf(address(this)), 1, "ORDER_BALANCE");
        assertEq(bookManager.ownerOf(OrderId.unwrap(id)), address(this), "ORDER_OWNER");
    }

    function testClaimShouldBurnWithZeroPendingOrder() public {
        uint64 makeAmount = 10000;
        Tick tick = Tick.wrap(100000);

        (OrderId id,) = makeRouter.make{value: 100 ether}(
            IBookManager.MakeParams({key: nativeQuoteKey, tick: tick, amount: makeAmount, provider: address(0)}), ""
        );

        takeRouter.take(IBookManager.TakeParams({key: nativeQuoteKey, maxAmount: makeAmount}), "");

        uint256 beforeQuoteAmount = address(this).balance;
        uint256 beforeBaseAmount = mockErc20.balanceOf(address(this));
        uint256 beforeQuoteReserve = bookManager.reservesOf(nativeQuoteKey.quote);
        uint256 beforeBaseReserve = bookManager.reservesOf(nativeQuoteKey.base);

        bookManager.approve(address(claimRouter), OrderId.unwrap(id));
        vm.expectEmit(address(bookManager));
        emit IBookManager.Claim(id, makeAmount);
        claimRouter.claim(id, "");

        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(id);

        assertEq(address(this).balance, beforeQuoteAmount, "QUOTE_BALANCE");
        assertEq(
            mockErc20.balanceOf(address(this)),
            beforeBaseAmount + tick.quoteToBase(uint256(makeAmount) * nativeQuoteKey.unit, false),
            "BASE_BALANCE"
        );
        assertEq(bookManager.reservesOf(nativeQuoteKey.quote), beforeQuoteReserve, "RESERVES_QUOTE");
        assertEq(
            bookManager.reservesOf(nativeQuoteKey.base),
            beforeBaseReserve - tick.quoteToBase(uint256(makeAmount) * nativeQuoteKey.unit, false),
            "RESERVES_BASE"
        );
        assertEq(bookManager.getDepth(nativeQuoteKey.toId(), tick), 0, "DEPTH");
        vm.expectRevert(abi.encodeWithSelector(TickBitmap.EmptyError.selector));
        bookManager.getLowest(nativeQuoteKey.toId());
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
