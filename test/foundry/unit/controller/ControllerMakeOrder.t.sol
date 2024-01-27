// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../Constants.sol";
import "../../../../contracts/libraries/BookId.sol";
import "../../../../contracts/libraries/Hooks.sol";
import "../../../../contracts/Controller.sol";
import "../../../../contracts/BookManager.sol";
import "../../mocks/MockERC20.sol";

contract ControllerMakeOrderTest is Test {
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
            base: CurrencyLibrary.NATIVE,
            unit: 1e12,
            quote: Currency.wrap(address(mockErc20)),
            makerPolicy: IBookManager.FeePolicy({rate: 0, useOutput: true}),
            takerPolicy: IBookManager.FeePolicy({rate: 0, useOutput: true}),
            hooks: IHooks(address(0))
        });
        unopenedKey = key;
        unopenedKey.unit = 1e11;

        manager = new BookManager(address(this), Constants.DEFAULT_PROVIDER, "url", "name", "symbol");
        manager.open(key, "");

        controller = new Controller(address(manager));
    }

    function _makeOrder(IBookManager.BookKey memory key, int24 tick, uint256 quoteAmount, address maker)
        internal
        returns (OrderId id)
    {
        mockErc20.mint(maker, quoteAmount);
        IController.MakeOrderParams[] memory paramsList = new IController.MakeOrderParams[](1);
        IController.ERC20PermitParams[] memory relatedTokenList = new IController.ERC20PermitParams[](1);
        IController.PermitSignature memory signature;
        relatedTokenList[0] =
            IController.ERC20PermitParams({token: address(mockErc20), permitAmount: 0, signature: signature});
        paramsList[0] = IController.MakeOrderParams({
            id: key.toId(),
            tick: Tick.wrap(tick),
            quoteAmount: quoteAmount,
            claimBounty: 0,
            hookData: ""
        });

        vm.startPrank(maker);
        mockErc20.approve(address(controller), quoteAmount);
        id = controller.make(paramsList, relatedTokenList, uint64(block.timestamp))[0];
        vm.stopPrank();
    }

    function testMakeOrder() public {
        OrderId id = _makeOrder(key, Constants.PRICE_TICK, Constants.QUOTE_AMOUNT1, Constants.MAKER1);

        (BookId bookId,,) = id.decode();

        assertEq(manager.ownerOf(OrderId.unwrap(id)), Constants.MAKER1);
        (address provider, uint256 price, uint256 openQuoteAmount, uint256 claimableQuoteAmount) =
            controller.getOrder(id);
        assertEq(Constants.QUOTE_AMOUNT1 - openQuoteAmount, mockErc20.balanceOf(Constants.MAKER1));
        assertEq(controller.toPrice(Tick.wrap(Constants.PRICE_TICK)), price);
        assertEq(claimableQuoteAmount, 0);
        assertEq(provider, address(0));
    }
}
