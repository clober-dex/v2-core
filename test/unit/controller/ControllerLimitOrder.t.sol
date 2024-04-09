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

contract ControllerLimitOrderTest is ControllerTest {
    using BookIdLibrary for IBookManager.BookKey;
    using FeePolicyLibrary for FeePolicy;
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;
    using Hooks for IHooks;

    OrderId public orderId;
    IBookManager.BookKey public takeBookKey;

    function setUp() public {
        mockErc20 = new MockERC20("Mock", "MOCK", 18);

        key = IBookManager.BookKey({
            base: Currency.wrap(address(mockErc20)),
            unit: 1e12,
            quote: CurrencyLibrary.NATIVE,
            makerPolicy: FeePolicyLibrary.encode(true, -100),
            takerPolicy: FeePolicyLibrary.encode(true, 100),
            hooks: IHooks(address(0))
        });

        takeBookKey = IBookManager.BookKey({
            base: CurrencyLibrary.NATIVE,
            unit: 1e12,
            quote: Currency.wrap(address(mockErc20)),
            makerPolicy: FeePolicyLibrary.encode(true, -100),
            takerPolicy: FeePolicyLibrary.encode(true, 100),
            hooks: IHooks(address(0))
        });

        manager = new BookManager(address(this), Constants.DEFAULT_PROVIDER, "baseUrl", "contractUrl", "name", "symbol");
        controller = new Controller(address(manager));
        bookViewer = new BookViewer(manager);
        IController.OpenBookParams[] memory openBookParamsList = new IController.OpenBookParams[](2);
        openBookParamsList[0] = IController.OpenBookParams({key: key, hookData: ""});
        openBookParamsList[1] = IController.OpenBookParams({key: takeBookKey, hookData: ""});
        controller.open(openBookParamsList, uint64(block.timestamp));

        vm.deal(Constants.MAKER1, 1000 * 10 ** 18);
        vm.deal(Constants.MAKER2, 1000 * 10 ** 18);
        vm.deal(Constants.MAKER3, 1000 * 10 ** 18);

        mockErc20.mint(Constants.MAKER1, 1000 * 10 ** 18);

        IController.MakeOrderParams[] memory paramsList = new IController.MakeOrderParams[](1);
        address[] memory tokensToSettle = new address[](1);
        tokensToSettle[0] = address(mockErc20);
        IController.ERC20PermitParams[] memory permitParamsList;
        paramsList[0] = IController.MakeOrderParams({
            id: takeBookKey.toId(),
            tick: Tick.wrap(0),
            quoteAmount: Constants.QUOTE_AMOUNT3,
            hookData: ""
        });

        vm.startPrank(Constants.MAKER1);
        mockErc20.approve(address(controller), type(uint256).max);
        controller.make{value: Constants.QUOTE_AMOUNT3}(
            paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp)
        )[0];
        vm.stopPrank();

        _makeOrder(Constants.PRICE_TICK, Constants.QUOTE_AMOUNT1, Constants.MAKER1);
    }

    function testLimitOrder() public {
        uint256 quoteAmount = 199999999880000000000;
        uint256 takeAmount = 93999999060000000000;

        uint256 beforeBalance = Constants.MAKER2.balance;
        uint256 beforeTokenBalance = mockErc20.balanceOf(Constants.MAKER2);
        _limitOrder(Constants.PRICE_TICK, Constants.QUOTE_AMOUNT1, Constants.MAKER2, takeBookKey);
        assertEq(quoteAmount, beforeBalance - Constants.MAKER2.balance);
        assertEq(beforeTokenBalance + takeAmount, mockErc20.balanceOf(Constants.MAKER2));
    }
}
