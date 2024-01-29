// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../Constants.sol";
import "../../../../contracts/libraries/BookId.sol";
import "../../../../contracts/libraries/Hooks.sol";
import "../../../../contracts/Controller.sol";
import "../../../../contracts/BookManager.sol";
import "../../mocks/MockERC20.sol";

contract ControllerTakeOrderTest is Test {
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;
    using BookIdLibrary for IBookManager.BookKey;
    using Hooks for IHooks;

    MockERC20 public mockErc20;

    IBookManager.BookKey public key;
    IBookManager.BookKey public unopenedKey;
    IBookManager public manager;
    Controller public controller;

    function setUp() public {
        mockErc20 = new MockERC20("Mock", "MOCK", 18);

        key = IBookManager.BookKey({
            base: Currency.wrap(address(mockErc20)),
            unit: 1e12,
            quote: CurrencyLibrary.NATIVE,
            makerPolicy: FeePolicyLibrary.encode(true, 0),
            takerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: IHooks(address(0))
        });
        unopenedKey = key;
        unopenedKey.unit = 1e11;

        manager = new BookManager(address(this), Constants.DEFAULT_PROVIDER, "baseUrl", "contractUrl", "name", "symbol");
        manager.open(key, "");

        controller = new Controller(address(manager));

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
            claimBounty: 0,
            hookData: ""
        });

        vm.prank(maker);
        id = controller.make{value: quoteAmount}(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp))[0];
    }

    function _takeOrder(uint256 quoteAmount, uint256 maxBaseAmount, address taker) internal {
        IController.TakeOrderParams[] memory paramsList = new IController.TakeOrderParams[](1);
        address[] memory tokensToSettle = new address[](1);
        tokensToSettle[0] = address(mockErc20);
        IController.ERC20PermitParams[] memory permitParamsList;
        paramsList[0] = IController.TakeOrderParams({
            id: key.toId(),
            limitPrice: type(uint256).max,
            quoteAmount: quoteAmount,
            maxBaseAmount: maxBaseAmount,
            hookData: ""
        });

        vm.startPrank(taker);
        mockErc20.approve(address(controller), maxBaseAmount);
        controller.take(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp));
        vm.stopPrank();
    }

    function testTakeOrder() public {
        uint256 takeAmount = 152000001000000000000;
        uint256 baseAmount = Tick.wrap(Constants.PRICE_TICK).quoteToBase(takeAmount, true);

        uint256 beforeBalance = Constants.TAKER1.balance;
        uint256 beforeTokenBalance = mockErc20.balanceOf(Constants.TAKER1);
        _takeOrder(Constants.QUOTE_AMOUNT2, type(uint256).max, Constants.TAKER1);
        assertEq(Constants.TAKER1.balance - beforeBalance, takeAmount);
        assertEq(beforeTokenBalance - mockErc20.balanceOf(Constants.TAKER1), baseAmount);
    }

    function testTake3TickOrder() public {
        uint256 takeAmount = 500000001000000000000;
        uint256 baseAmount = Tick.wrap(Constants.PRICE_TICK).quoteToBase(200000000000000000000, true)
            + Tick.wrap(Constants.PRICE_TICK + 1).quoteToBase(246000000000000000000, true)
            + Tick.wrap(Constants.PRICE_TICK + 2).quoteToBase(54000001000000000000, true);

        uint256 beforeBalance = Constants.TAKER1.balance;
        uint256 beforeTokenBalance = mockErc20.balanceOf(Constants.TAKER1);
        _takeOrder(Constants.QUOTE_AMOUNT4, type(uint256).max, Constants.TAKER1);
        assertEq(Constants.TAKER1.balance - beforeBalance, takeAmount);
        assertEq(beforeTokenBalance - mockErc20.balanceOf(Constants.TAKER1), baseAmount);
    }

    //    function testTakeLimitPriceOrder() public {
    //        uint256 takeAmount = 500000001000000000000;
    //        uint256 baseAmount = Tick.wrap(Constants.PRICE_TICK).quoteToBase(200000000000000000000, true)
    //            + Tick.wrap(Constants.PRICE_TICK + 1).quoteToBase(246000000000000000000, true)
    //            + Tick.wrap(Constants.PRICE_TICK + 2).quoteToBase(54000001000000000000, true);
    //
    //        uint256 beforeBalance = Constants.TAKER1.balance;
    //        uint256 beforeTokenBalance = mockErc20.balanceOf(Constants.TAKER1);
    //        _takeOrder(
    //            Constants.QUOTE_AMOUNT4, type(uint256).max, Tick.wrap(Constants.PRICE_TICK).toPrice(), Constants.TAKER1
    //        );
    //        assertEq(Constants.TAKER1.balance - beforeBalance, takeAmount);
    //        assertEq(beforeTokenBalance - mockErc20.balanceOf(Constants.TAKER1), baseAmount);
    //    }
}
