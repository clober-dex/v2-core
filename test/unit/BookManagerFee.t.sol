// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/BookManager.sol";
import "../../src/mocks/MockERC20.sol";
import "../routers/MakeRouter.sol";
import "../routers/TakeRouter.sol";
import "../routers/OpenRouter.sol";
import "../routers/ClaimRouter.sol";

contract BookManagerFee is Test {
    using BookIdLibrary for IBookManager.BookKey;
    using OrderIdLibrary for OrderId;
    using TickLibrary for Tick;
    using FeePolicyLibrary for FeePolicy;

    address public constant DEFAULT_PROVIDER = address(0x1312);
    int24 private constant _MAX_FEE_RATE = 10 ** 6 / 2;
    int24 private constant _MIN_FEE_RATE = -(10 ** 6 / 2);

    BookManager public bookManager;

    MockERC20 public quote;
    MockERC20 public base;
    OpenRouter public openRouter;
    MakeRouter public makeRouter;
    TakeRouter public takeRouter;
    ClaimRouter public claimRouter;

    receive() external payable {}

    function setUp() public {
        bookManager = new BookManager(address(this), DEFAULT_PROVIDER, "URI", "URI", "name", "SYMBOL");

        quote = new MockERC20("Mock", "MOCK", 6);
        base = new MockERC20("Mock", "MOCK", 18);

        openRouter = new OpenRouter(bookManager);
        makeRouter = new MakeRouter(bookManager);
        takeRouter = new TakeRouter(bookManager);
        claimRouter = new ClaimRouter(bookManager);
        quote.mint(address(this), 100 * 1e6);
        quote.approve(address(makeRouter), type(uint256).max);
        quote.approve(address(takeRouter), type(uint256).max);
        base.mint(address(this), 100 ether);
        base.approve(address(makeRouter), type(uint256).max);
        base.approve(address(takeRouter), type(uint256).max);
    }

    function _openMarket(FeePolicy maker, FeePolicy taker) internal returns (IBookManager.BookKey memory key) {
        key = IBookManager.BookKey({
            base: Currency.wrap(address(base)),
            unitSize: 1,
            quote: Currency.wrap(address(quote)),
            makerPolicy: maker,
            takerPolicy: taker,
            hooks: IHooks(address(0))
        });

        openRouter.open(key, "");
    }

    function testMakeFeeUsePositiveQuoteRate() public {
        IBookManager.BookKey memory key =
            _openMarket(FeePolicyLibrary.encode(true, 3000), FeePolicyLibrary.encode(false, 3000));

        uint256 beforeBalance = quote.balanceOf(address(this));

        (OrderId id, uint256 quoteAmount) = makeRouter.make(
            IBookManager.MakeParams({key: key, tick: Tick.wrap(0), unit: 1000, provider: address(0)}), ""
        );

        assertEq(quote.balanceOf(address(this)), beforeBalance - 1003, "QUOTE_BALANCE");
        assertEq(quoteAmount, 1003, "QUOTE_AMOUNT");
        assertEq(bookManager.getOrder(id).open, 1000, "OPEN_AMOUNT");
    }

    function testMakeFeeUseNegativeQuoteRate() public {
        IBookManager.BookKey memory key =
            _openMarket(FeePolicyLibrary.encode(true, -3000), FeePolicyLibrary.encode(true, 5000));

        uint256 beforeBalance = quote.balanceOf(address(this));

        (OrderId id, uint256 quoteAmount) = makeRouter.make(
            IBookManager.MakeParams({key: key, tick: Tick.wrap(0), unit: 1000, provider: address(0)}), ""
        );

        assertEq(quote.balanceOf(address(this)), beforeBalance - 997, "QUOTE_BALANCE");
        assertEq(quoteAmount, 997, "QUOTE_AMOUNT");
        assertEq(bookManager.getOrder(id).open, 1000, "OPEN_AMOUNT");
    }

    function testTakeFeeUsePositiveQuoteRate() public {
        IBookManager.BookKey memory key =
            _openMarket(FeePolicyLibrary.encode(true, 0), FeePolicyLibrary.encode(true, 3000));
        makeRouter.make(IBookManager.MakeParams({key: key, tick: Tick.wrap(0), unit: 2000, provider: address(0)}), "");

        uint256 beforeQuote = quote.balanceOf(address(this));
        uint256 beforeBase = base.balanceOf(address(this));

        (uint256 quoteAmount, uint256 baseAmount) = takeRouter.take(
            IBookManager.TakeParams({key: key, tick: bookManager.getHighest(key.toId()), maxUnit: 1000}), ""
        );

        assertEq(quote.balanceOf(address(this)), beforeQuote + 997, "QUOTE_BALANCE");
        assertEq(base.balanceOf(address(this)), beforeBase - 1000, "BASE_BALANCE");
        assertEq(quoteAmount, 997, "QUOTE_AMOUNT");
        assertEq(baseAmount, 1000, "BASE_AMOUNT");
    }

    function testTakeFeeUseNegativeQuoteRate() public {
        IBookManager.BookKey memory key =
            _openMarket(FeePolicyLibrary.encode(true, 5000), FeePolicyLibrary.encode(true, -3000));
        makeRouter.make(IBookManager.MakeParams({key: key, tick: Tick.wrap(0), unit: 2000, provider: address(0)}), "");

        uint256 beforeQuote = quote.balanceOf(address(this));
        uint256 beforeBase = base.balanceOf(address(this));

        (uint256 quoteAmount, uint256 baseAmount) = takeRouter.take(
            IBookManager.TakeParams({key: key, tick: bookManager.getHighest(key.toId()), maxUnit: 1000}), ""
        );

        assertEq(quote.balanceOf(address(this)), beforeQuote + 1003, "QUOTE_BALANCE");
        assertEq(base.balanceOf(address(this)), beforeBase - 1000, "BASE_BALANCE");
        assertEq(quoteAmount, 1003, "QUOTE_AMOUNT");
        assertEq(baseAmount, 1000, "BASE_AMOUNT");
    }

    function testTakeFeeUsePositiveBaseRate() public {
        IBookManager.BookKey memory key =
            _openMarket(FeePolicyLibrary.encode(true, 3000), FeePolicyLibrary.encode(false, 3000));
        makeRouter.make(IBookManager.MakeParams({key: key, tick: Tick.wrap(0), unit: 2000, provider: address(0)}), "");

        uint256 beforeQuote = quote.balanceOf(address(this));
        uint256 beforeBase = base.balanceOf(address(this));

        (uint256 quoteAmount, uint256 baseAmount) = takeRouter.take(
            IBookManager.TakeParams({key: key, tick: bookManager.getHighest(key.toId()), maxUnit: 1000}), ""
        );

        assertEq(quote.balanceOf(address(this)), beforeQuote + 1000, "QUOTE_BALANCE");
        assertEq(base.balanceOf(address(this)), beforeBase - 1003, "BASE_BALANCE");
        assertEq(quoteAmount, 1000, "QUOTE_AMOUNT");
        assertEq(baseAmount, 1003, "BASE_AMOUNT");
    }

    function testTakeFeeUseNegativeBaseRate() public {
        IBookManager.BookKey memory key =
            _openMarket(FeePolicyLibrary.encode(false, 5000), FeePolicyLibrary.encode(false, -3000));
        makeRouter.make(IBookManager.MakeParams({key: key, tick: Tick.wrap(0), unit: 2000, provider: address(0)}), "");

        uint256 beforeQuote = quote.balanceOf(address(this));
        uint256 beforeBase = base.balanceOf(address(this));

        (uint256 quoteAmount, uint256 baseAmount) = takeRouter.take(
            IBookManager.TakeParams({key: key, tick: bookManager.getHighest(key.toId()), maxUnit: 1000}), ""
        );

        assertEq(quote.balanceOf(address(this)), beforeQuote + 1000, "QUOTE_BALANCE");
        assertEq(base.balanceOf(address(this)), beforeBase - 997, "BASE_BALANCE");
        assertEq(quoteAmount, 1000, "QUOTE_AMOUNT");
        assertEq(baseAmount, 997, "BASE_AMOUNT");
    }

    function testClaimFeeUsePositiveBaseRate() public {
        IBookManager.BookKey memory key =
            _openMarket(FeePolicyLibrary.encode(false, 3000), FeePolicyLibrary.encode(false, 3000));
        (OrderId id,) = makeRouter.make(
            IBookManager.MakeParams({key: key, tick: Tick.wrap(0), unit: 2000, provider: address(0)}), ""
        );
        takeRouter.take(
            IBookManager.TakeParams({key: key, tick: bookManager.getHighest(key.toId()), maxUnit: 1000}), ""
        );

        uint256 beforeQuote = quote.balanceOf(address(this));
        uint256 beforeBase = base.balanceOf(address(this));

        bookManager.approve(address(claimRouter), OrderId.unwrap(id));
        claimRouter.claim(id, "");

        assertEq(quote.balanceOf(address(this)), beforeQuote, "QUOTE_BALANCE");
        assertEq(base.balanceOf(address(this)), beforeBase + 997, "BASE_BALANCE");
    }

    function testClaimFeeUseNegativeBaseRate() public {
        IBookManager.BookKey memory key =
            _openMarket(FeePolicyLibrary.encode(false, -3000), FeePolicyLibrary.encode(false, 5000));
        (OrderId id,) = makeRouter.make(
            IBookManager.MakeParams({key: key, tick: Tick.wrap(0), unit: 2000, provider: address(0)}), ""
        );
        takeRouter.take(
            IBookManager.TakeParams({key: key, tick: bookManager.getHighest(key.toId()), maxUnit: 1000}), ""
        );

        uint256 beforeQuote = quote.balanceOf(address(this));
        uint256 beforeBase = base.balanceOf(address(this));

        bookManager.approve(address(claimRouter), OrderId.unwrap(id));
        claimRouter.claim(id, "");

        assertEq(quote.balanceOf(address(this)), beforeQuote, "QUOTE_BALANCE");
        assertEq(base.balanceOf(address(this)), beforeBase + 1003, "BASE_BALANCE");
    }
}
