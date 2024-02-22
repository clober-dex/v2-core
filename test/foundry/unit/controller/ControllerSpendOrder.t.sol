// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../Constants.sol";
import "../../../../contracts/libraries/BookId.sol";
import "../../../../contracts/libraries/Hooks.sol";
import "../../../../contracts/Controller.sol";
import "../../../../contracts/BookManager.sol";
import "../../mocks/MockERC20.sol";

contract ControllerSpendOrderTest is Test {
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;
    using BookIdLibrary for IBookManager.BookKey;
    using Hooks for IHooks;

    MockERC20 public mockErc20;

    IBookManager.BookKey public key;
    IBookManager.BookKey public unopenedKey;
    IBookManager public manager;
    OrderId public orderId;
    Controller public controller;

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
        unopenedKey = key;
        unopenedKey.unit = 1e11;

        manager = new BookManager(address(this), Constants.DEFAULT_PROVIDER, "baseUrl", "contractUrl", "name", "symbol");
        controller = new Controller(address(manager));
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
        _makeOrder(Constants.PRICE_TICK + 2, Constants.QUOTE_AMOUNT2, Constants.MAKER1);
    }

    function _makeOrder(int24 tick, uint256 quoteAmount, address maker) internal returns (OrderId id) {
        IController.MakeOrderParams[] memory paramsList = new IController.MakeOrderParams[](1);
        address[] memory tokensToSettle;
        IController.ERC20PermitParams[] memory permitParamsList;
        paramsList[0] = IController.MakeOrderParams({
            id: key.toId(),
            tick: Tick.wrap(tick),
            quoteAmount: quoteAmount,
            hookData: ""
        });

        vm.prank(maker);
        id = controller.make{value: quoteAmount}(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp))[0];
    }

    function _spendOrder(uint256 baseAmount, address taker) internal {
        IController.SpendOrderParams[] memory paramsList = new IController.SpendOrderParams[](1);
        address[] memory tokensToSettle = new address[](1);
        tokensToSettle[0] = address(mockErc20);
        IController.ERC20PermitParams[] memory permitParamsList;
        paramsList[0] = IController.SpendOrderParams({
            id: key.toId(),
            limitPrice: type(uint256).max,
            baseAmount: baseAmount,
            hookData: ""
        });

        vm.startPrank(taker);
        mockErc20.approve(address(controller), baseAmount);
        controller.spend(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp));
        vm.stopPrank();
    }

    function testSpendOrder() public {
        uint256 baseAmount = 11999999954734344903;
        uint256 takeAmount = Tick.wrap(Constants.PRICE_TICK).baseToQuote(baseAmount, false);

        uint256 beforeBalance = Constants.TAKER1.balance;
        uint256 beforeTokenBalance = mockErc20.balanceOf(Constants.TAKER1);
        _spendOrder(Constants.BASE_AMOUNT1, Constants.TAKER1);
        assertEq(Constants.TAKER1.balance - beforeBalance, takeAmount);
        assertEq(beforeTokenBalance - mockErc20.balanceOf(Constants.TAKER1), baseAmount);
    }
}
