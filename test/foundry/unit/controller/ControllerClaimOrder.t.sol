// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../Constants.sol";
import "../../../../contracts/libraries/BookId.sol";
import "../../../../contracts/libraries/Hooks.sol";
import "../../../../contracts/Controller.sol";
import "../../../../contracts/BookManager.sol";
import "../../mocks/MockERC20.sol";

contract ControllerClaimOrderTest is Test {
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

        orderId1 = _makeOrder(Constants.PRICE_TICK, Constants.QUOTE_AMOUNT2, Constants.MAKER1);
        orderId2 = _makeOrder(Constants.PRICE_TICK + 1, Constants.QUOTE_AMOUNT1, Constants.MAKER2);
        _takeOrder(Constants.QUOTE_AMOUNT1, type(uint256).max, Constants.TAKER1);
    }

    function _makeOrder(int24 tick, uint256 quoteAmount, address maker) internal returns (OrderId id) {
        IController.MakeOrderParams[] memory paramsList = new IController.MakeOrderParams[](1);
        IController.ERC20PermitParams[] memory relatedTokenList;
        paramsList[0] = IController.MakeOrderParams({
            id: key.toId(),
            tick: Tick.wrap(tick),
            quoteAmount: quoteAmount,
            claimBounty: 0,
            hookData: ""
        });

        vm.prank(maker);
        id = controller.make{value: quoteAmount}(paramsList, relatedTokenList, uint64(block.timestamp))[0];
    }

    function _takeOrder(uint256 quoteAmount, uint256 maxBaseAmount, address taker) internal {
        IController.TakeOrderParams[] memory paramsList = new IController.TakeOrderParams[](1);
        IController.ERC20PermitParams[] memory relatedTokenList = new IController.ERC20PermitParams[](1);
        IController.PermitSignature memory signature;
        relatedTokenList[0] =
            IController.ERC20PermitParams({token: address(mockErc20), permitAmount: 0, signature: signature});
        paramsList[0] = IController.TakeOrderParams({
            id: key.toId(),
            limitPrice: type(uint256).max,
            quoteAmount: quoteAmount,
            maxBaseAmount: maxBaseAmount,
            hookData: ""
        });

        vm.startPrank(taker);
        mockErc20.approve(address(controller), maxBaseAmount);
        controller.take(paramsList, relatedTokenList, uint64(block.timestamp));
        vm.stopPrank();
    }

    function _claimOrder(OrderId id) internal {
        IController.ClaimOrderParams[] memory paramsList = new IController.ClaimOrderParams[](1);
        IController.PermitSignature memory signature;
        paramsList[0] = IController.ClaimOrderParams({id: id, hookData: "", permitParams: signature});

        controller.claim(paramsList, uint64(block.timestamp));
    }

    function testClaimAllOrder() public {
        uint256 beforeBalance = mockErc20.balanceOf(Constants.MAKER1);
        (,, uint256 openQuoteAmount, uint256 claimableAmount) = controller.getOrder(orderId1);
        _claimOrder(orderId1);
        assertEq(mockErc20.balanceOf(Constants.MAKER1) - beforeBalance, claimableAmount);
        (,, openQuoteAmount, claimableAmount) = controller.getOrder(orderId1);
        assertEq(claimableAmount, 0);
    }

    function testClaimPartialOrder() public {
        uint256 beforeBalance = mockErc20.balanceOf(Constants.MAKER2);
        (,,, uint256 claimableAmount) = controller.getOrder(orderId2);
        _claimOrder(orderId2);
        assertEq(mockErc20.balanceOf(Constants.MAKER2) - beforeBalance, claimableAmount);
        (,,, claimableAmount) = controller.getOrder(orderId2);
        assertEq(claimableAmount, 0);
    }
}
