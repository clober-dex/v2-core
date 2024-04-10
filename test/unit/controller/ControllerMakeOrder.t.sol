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

contract ControllerMakeOrderTest is ControllerTest {
    using FeePolicyLibrary for FeePolicy;
    using OrderIdLibrary for OrderId;
    using Hooks for IHooks;

    OrderId public orderId;

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

        manager = new BookManager(address(this), Constants.DEFAULT_PROVIDER, "baseUrl", "contractUrl", "name", "symbol");
        controller = new Controller(address(manager));
        bookViewer = new BookViewer(manager);
        IController.OpenBookParams[] memory openBookParamsList = new IController.OpenBookParams[](1);
        openBookParamsList[0] = IController.OpenBookParams({key: key, hookData: ""});
        controller.open(openBookParamsList, uint64(block.timestamp));

        vm.deal(Constants.MAKER1, 1000 * 10 ** 18);
        vm.deal(Constants.MAKER2, 1000 * 10 ** 18);
        vm.deal(Constants.MAKER3, 1000 * 10 ** 18);
    }

    function testMakeOrder() public {
        uint256 beforeBalance = Constants.MAKER1.balance;
        OrderId id = _makeOrder(Constants.PRICE_TICK, Constants.QUOTE_AMOUNT1, Constants.MAKER1);

        assertEq(manager.ownerOf(OrderId.unwrap(id)), Constants.MAKER1);
        (address provider, uint256 price, uint256 openQuoteAmount, uint256 claimableQuoteAmount) =
            controller.getOrder(id);
        assertEq(
            openQuoteAmount - uint256(-key.makerPolicy.calculateFee(openQuoteAmount, true)),
            beforeBalance - Constants.MAKER1.balance
        );
        assertEq(controller.toPrice(Tick.wrap(Constants.PRICE_TICK)), price);
        assertEq(claimableQuoteAmount, 0);
        assertEq(provider, address(0));
    }
}
