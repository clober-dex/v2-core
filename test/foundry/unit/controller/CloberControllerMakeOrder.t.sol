// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../Constants.sol";
import "../../../../contracts/libraries/BookId.sol";
import "../../../../contracts/libraries/Hooks.sol";
import "../../../../contracts/controller/CloberController.sol";
import "../../../../contracts/BookManager.sol";
import "../../mocks/MockERC20.sol";

contract CloberControllerMakeOrderTest is Test {
    using OrderIdLibrary for OrderId;
    using BookIdLibrary for IBookManager.BookKey;
    using Hooks for IHooks;

    MockERC20 public mockErc20;

    IBookManager.BookKey public key;
    IBookManager.BookKey public unopenedKey;
    IBookManager public manager;
    CloberController public cloberController;

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

        cloberController = new CloberController(address(manager));
    }

    function testMakeOrder() public {
        ICloberController.MakeOrderParams[] memory paramsList = new ICloberController.MakeOrderParams[](1);

        ICloberController.ERC20PermitParams memory params;

        mockErc20.mint(Constants.MAKER, Constants.QUOTE_AMOUNT);

        Tick tick = Tick.wrap(Constants.PRICE_TICK);
        paramsList[0] = ICloberController.MakeOrderParams({
            id: key.toId(),
            tick: Tick.wrap(Constants.PRICE_TICK),
            quoteAmount: Constants.QUOTE_AMOUNT,
            maker: Constants.MAKER,
            bounty: 0,
            hookData: "",
            permitParams: params
        });

        vm.startPrank(Constants.MAKER);
        mockErc20.approve(address(cloberController), Constants.QUOTE_AMOUNT);
        OrderId[] memory ids = cloberController.make(paramsList, uint64(block.timestamp));
        vm.stopPrank();

        (BookId bookId,, uint40 index) = ids[0].decode();
        IBookManager.OrderInfo memory orderInfo = manager.getOrder(ids[0]);

        assertEq(manager.ownerOf(OrderId.unwrap(ids[0])), Constants.MAKER);
        (address provider, uint256 price, uint256 openQuoteAmount, uint256 claimableQuoteAmount) =
            cloberController.getOrder(ids[0]);
        assertEq(Constants.QUOTE_AMOUNT - openQuoteAmount, mockErc20.balanceOf(Constants.MAKER));
        assertEq(cloberController.toPrice(tick), price);
    }
}
