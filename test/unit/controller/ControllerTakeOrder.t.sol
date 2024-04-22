// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./ControllerTest.sol";
import "../../Constants.sol";
import "../../../src/libraries/BookId.sol";
import "../../../src/libraries/Hooks.sol";
import "../../../src/Controller.sol";
import "../../../src/BookManager.sol";
import "../../../src/mocks/MockERC20.sol";

contract ControllerTakeOrderTest is ControllerTest {
    using FeePolicyLibrary for FeePolicy;
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;
    using Hooks for IHooks;

    function setUp() public {
        mockErc20 = new MockERC20("Mock", "MOCK", 18);

        key = IBookManager.BookKey({
            base: Currency.wrap(address(mockErc20)),
            unitSize: 1e12,
            quote: CurrencyLibrary.NATIVE,
            makerPolicy: FeePolicyLibrary.encode(true, 100),
            takerPolicy: FeePolicyLibrary.encode(true, 100),
            hooks: IHooks(address(0))
        });

        manager = new BookManager(address(this), Constants.DEFAULT_PROVIDER, "baseUrl", "contractUrl", "name", "symbol");
        controller = new Controller(address(manager));
        bookViewer = new BookViewer(manager);
        IController.OpenBookParams[] memory openBookParamsList = new IController.OpenBookParams[](1);
        openBookParamsList[0] = IController.OpenBookParams({key: key, hookData: ""});
        controller.open(openBookParamsList, uint64(block.timestamp));

        vm.deal(Constants.MAKER1, 1000 * 10 ** 18);
        vm.deal(Constants.MAKER2, 1000 * 10 ** 18);
        vm.deal(Constants.MAKER3, 1000 * 10 ** 18);

        mockErc20.mint(Constants.TAKER1, 1000 * 10 ** 18);
        mockErc20.mint(Constants.TAKER2, 1000 * 10 ** 18);
        mockErc20.mint(Constants.TAKER3, 1000 * 10 ** 18);

        _makeOrder(Constants.PRICE_TICK, Constants.QUOTE_AMOUNT1, Constants.MAKER1);
        _makeOrder(Constants.PRICE_TICK + 1, Constants.QUOTE_AMOUNT2, Constants.MAKER2);
        _makeOrder(Constants.PRICE_TICK + 1, Constants.QUOTE_AMOUNT3, Constants.MAKER3);
        _makeOrder(Constants.PRICE_TICK + 2, Constants.QUOTE_AMOUNT1, Constants.MAKER1);
    }

    function testTakeOrder() public {
        uint256 takeAmount = 152000000479800000000;
        uint256 baseAmount = Tick.wrap(Constants.PRICE_TICK + 2).quoteToBase(
            key.takerPolicy.calculateOriginalAmount(takeAmount, true), true
        );

        uint256 beforeBalance = Constants.TAKER1.balance;
        uint256 beforeTokenBalance = mockErc20.balanceOf(Constants.TAKER1);
        (uint256 expectedTakeAmount, uint256 expectedBaseAmount) =
            _takeOrder(Constants.QUOTE_AMOUNT2, type(uint256).max, Constants.TAKER1);
        assertEq(expectedTakeAmount, takeAmount);
        assertEq(expectedBaseAmount, baseAmount);
        assertEq(Constants.TAKER1.balance - beforeBalance, takeAmount);
        assertEq(beforeTokenBalance - mockErc20.balanceOf(Constants.TAKER1), baseAmount);
    }

    function testTake3TickOrder() public {
        uint256 takeAmount = 500000000999400000000;
        uint256 baseAmount = Tick.wrap(Constants.PRICE_TICK + 2).quoteToBase(
            key.takerPolicy.calculateOriginalAmount(199960002999900000000, true), true
        )
            + Tick.wrap(Constants.PRICE_TICK + 1).quoteToBase(
                key.takerPolicy.calculateOriginalAmount(245950803459900000000, true), true
            )
            + Tick.wrap(Constants.PRICE_TICK).quoteToBase(
                key.takerPolicy.calculateOriginalAmount(54089194539600000000, true), true
            );

        uint256 beforeBalance = Constants.TAKER1.balance;
        uint256 beforeTokenBalance = mockErc20.balanceOf(Constants.TAKER1);
        (uint256 expectedTakeAmount, uint256 expectedBaseAmount) =
            _takeOrder(Constants.QUOTE_AMOUNT4, type(uint256).max, Constants.TAKER1);
        assertEq(expectedTakeAmount, takeAmount, "TAKE_AMOUNT");
        assertEq(expectedBaseAmount, baseAmount, "BASE_AMOUNT");
        assertEq(Constants.TAKER1.balance - beforeBalance, takeAmount, "TAKER_BALANCE");
        assertEq(beforeTokenBalance - mockErc20.balanceOf(Constants.TAKER1), baseAmount, "TOKEN_BALANCE");
    }
}
