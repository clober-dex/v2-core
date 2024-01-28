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

        orderId = _makeOrder(key, Constants.PRICE_TICK, Constants.QUOTE_AMOUNT1, Constants.MAKER1);
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

    function _spendOrder(IBookManager.BookKey memory key, uint256 baseAmount, uint256 minQuoteAmount, address taker)
        internal
    {
        IController.SpendOrderParams[] memory paramsList = new IController.SpendOrderParams[](1);
        IController.ERC20PermitParams[] memory relatedTokenList = new IController.ERC20PermitParams[](1);
        IController.PermitSignature memory signature;
        relatedTokenList[0] =
            IController.ERC20PermitParams({token: address(mockErc20), permitAmount: 0, signature: signature});
        paramsList[0] = IController.SpendOrderParams({
            id: key.toId(),
            limitPrice: type(uint256).max,
            baseAmount: baseAmount,
            minQuoteAmount: minQuoteAmount,
            hookData: ""
        });

        vm.prank(taker);
        controller.spend{value: baseAmount}(paramsList, relatedTokenList, uint64(block.timestamp));
    }

    function testSpendOrder() public {
        vm.deal(Constants.TAKER1, type(uint256).max);

        uint256 lowestPrice = controller.getLowestPrice(key.toId());
        uint256 beforeBalance = Constants.TAKER1.balance;
        uint256 quoteAmount = Constants.BASE_AMOUNT1 * lowestPrice >> 128;
        _spendOrder(key, Constants.BASE_AMOUNT1, quoteAmount, Constants.TAKER1);
        assertEq(mockErc20.balanceOf(Constants.TAKER1), quoteAmount);
        assertEq(beforeBalance - Constants.TAKER1.balance, Constants.BASE_AMOUNT1);
    }
}
