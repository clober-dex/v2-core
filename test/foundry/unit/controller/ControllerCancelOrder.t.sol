// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../Constants.sol";
import "../../../../contracts/libraries/BookId.sol";
import "../../../../contracts/libraries/Hooks.sol";
import "../../../../contracts/Controller.sol";
import "../../../../contracts/BookManager.sol";
import "../../mocks/MockERC20.sol";

contract ControllerCancelOrderTest is Test {
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;
    using BookIdLibrary for IBookManager.BookKey;
    using Hooks for IHooks;

    MockERC20 public mockErc20;

    IBookManager.BookKey public key;
    IBookManager.BookKey public unopenedKey;
    IBookManager public manager;
    Controller public controller;
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

        orderId1 = _makeOrder(Constants.PRICE_TICK, Constants.QUOTE_AMOUNT1, Constants.MAKER1);
        orderId2 = _makeOrder(Constants.PRICE_TICK + 1, Constants.QUOTE_AMOUNT1, Constants.MAKER2);
        _takeOrder(Constants.QUOTE_AMOUNT2, type(uint256).max, Constants.TAKER1);
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

    function _cancelOrder(OrderId id, uint256 to) internal {
        IController.CancelOrderParams[] memory paramsList = new IController.CancelOrderParams[](1);
        IController.PermitSignature memory signature;
        IController.ERC721PermitParams[] memory permitParamsList = new IController.ERC721PermitParams[](1);
        permitParamsList[0] = IController.ERC721PermitParams({tokenId: OrderId.unwrap(id), signature: signature});

        paramsList[0] = IController.CancelOrderParams({id: id, leftQuoteAmount: to, hookData: ""});

        vm.startPrank(manager.ownerOf(OrderId.unwrap(id)));
        manager.approve(address(controller), OrderId.unwrap(id));
        controller.cancel(paramsList, permitParamsList, uint64(block.timestamp));
        vm.stopPrank();
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
        uint256 cancelToAmount = openAmount / 3;
        _cancelOrder(orderId2, cancelToAmount);
        assertEq(Constants.MAKER2.balance - beforeBalance, 133333334000000000000);
        (,, openAmount,) = controller.getOrder(orderId2);
        assertEq(openAmount, 66666666000000000000);
    }
}
