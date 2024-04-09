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

contract ControllerCancelOrderTest is ControllerTest {
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;
    using Hooks for IHooks;

    OrderId public orderId1;
    OrderId public orderId2;

    function setUp() public {
        mockErc20 = new MockERC20("Mock", "MOCK", 18);

        key = IBookManager.BookKey({
            base: Currency.wrap(address(mockErc20)),
            unit: 1e12,
            quote: CurrencyLibrary.NATIVE,
            makerPolicy: FeePolicyLibrary.encode(false, 0),
            takerPolicy: FeePolicyLibrary.encode(true, 0),
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

        orderId1 = _makeOrder(Constants.PRICE_TICK, Constants.QUOTE_AMOUNT1, Constants.MAKER1);
        orderId2 = _makeOrder(Constants.PRICE_TICK + 1, Constants.QUOTE_AMOUNT1, Constants.MAKER2);
        _takeOrder(Constants.QUOTE_AMOUNT2, type(uint256).max, Constants.TAKER1);
    }

    function testCancelAllOrder() public {
        uint256 beforeBalance = Constants.MAKER2.balance;
        (,, uint256 openAmount,) = controller.getOrder(orderId2);
        _cancelOrder(orderId2, 0);
        assertEq(Constants.MAKER2.balance - beforeBalance, openAmount);
        (,, openAmount,) = controller.getOrder(orderId2);
        assertEq(openAmount, 0);
    }

    function testCancelAllFilledOrder() public {
        uint256 beforeBalance = Constants.MAKER1.balance;
        (,, uint256 openAmount,) = controller.getOrder(orderId1);
        _cancelOrder(orderId1, 0);
        assertEq(Constants.MAKER1.balance - beforeBalance, openAmount);
        (,, openAmount,) = controller.getOrder(orderId1);
        assertEq(openAmount, 0);
    }

    function testCancelPartialOrder() public {
        uint256 beforeBalance = Constants.MAKER2.balance;
        (,, uint256 openAmount,) = controller.getOrder(orderId2);
        uint256 cancelToAmount = ((openAmount / 3) / 1e12) * 1e12;
        _cancelOrder(orderId2, cancelToAmount);
        assertEq(Constants.MAKER2.balance - beforeBalance, openAmount - cancelToAmount);
        (,, openAmount,) = controller.getOrder(orderId2);
        assertEq(openAmount, cancelToAmount);
    }
}
