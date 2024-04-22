// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../Constants.sol";
import "../../../src/libraries/BookId.sol";
import "../../../src/libraries/Hooks.sol";
import "../../../src/Controller.sol";
import "../../../src/BookManager.sol";
import "../../../src/mocks/MockERC20.sol";
import "../../../src/BookViewer.sol";

contract ControllerExecuteOrderTest is Test {
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;
    using BookIdLibrary for IBookManager.BookKey;
    using Hooks for IHooks;

    MockERC20 public mockErc20;

    IBookManager.BookKey public key;
    IBookManager public manager;
    Controller public controller;
    BookViewer public bookViewer;
    OrderId public orderId1;

    function setUp() public {
        mockErc20 = new MockERC20("Mock", "MOCK", 18);

        key = IBookManager.BookKey({
            base: Currency.wrap(address(mockErc20)),
            unitSize: 1e12,
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

        vm.deal(Constants.TAKER1, 1000 * 10 ** 18);
        mockErc20.mint(Constants.TAKER1, 1000 * 10 ** 18);

        IController.MakeOrderParams[] memory paramsList = new IController.MakeOrderParams[](1);
        IController.ERC20PermitParams[] memory permitParamsList;
        address[] memory tokensToSettle;
        paramsList[0] = _makeOrder(Constants.PRICE_TICK, Constants.QUOTE_AMOUNT3);

        vm.prank(Constants.MAKER1);
        manager.setApprovalForAll(address(controller), true);

        vm.prank(Constants.TAKER1);
        manager.setApprovalForAll(address(controller), true);

        vm.prank(Constants.MAKER1);
        orderId1 = controller.make{value: Constants.QUOTE_AMOUNT3}(
            paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp)
        )[0];
    }

    function _makeOrder(int24 tick, uint256 quoteAmount)
        internal
        view
        returns (IController.MakeOrderParams memory params)
    {
        params =
            IController.MakeOrderParams({id: key.toId(), tick: Tick.wrap(tick), quoteAmount: quoteAmount, hookData: ""});

        return params;
    }

    function _takeOrder(uint256 quoteAmount) internal view returns (IController.TakeOrderParams memory params) {
        params = IController.TakeOrderParams({
            id: key.toId(),
            limitPrice: 0,
            quoteAmount: quoteAmount,
            maxBaseAmount: type(uint256).max,
            hookData: ""
        });

        return params;
    }

    function _spendOrder(uint256 baseAmount) internal view returns (IController.SpendOrderParams memory params) {
        params = IController.SpendOrderParams({
            id: key.toId(),
            limitPrice: 0,
            baseAmount: baseAmount,
            minQuoteAmount: 0,
            hookData: ""
        });
    }

    function _claimOrder(OrderId id) internal pure returns (IController.ClaimOrderParams memory) {
        return IController.ClaimOrderParams({id: id, hookData: ""});
    }

    function _cancelOrder(OrderId id) internal pure returns (IController.CancelOrderParams memory) {
        return IController.CancelOrderParams({id: id, leftQuoteAmount: 0, hookData: ""});
    }

    function testExecuteOrder() public {
        IController.Action[] memory actionList = new IController.Action[](3);
        actionList[0] = IController.Action.MAKE;
        actionList[1] = IController.Action.TAKE;
        actionList[2] = IController.Action.SPEND;

        bytes[] memory paramsDataList = new bytes[](3);
        paramsDataList[0] = abi.encode(_makeOrder(Constants.PRICE_TICK + 2, Constants.QUOTE_AMOUNT3));
        paramsDataList[1] = abi.encode(_takeOrder(Constants.QUOTE_AMOUNT2));
        paramsDataList[2] = abi.encode(_spendOrder(Constants.BASE_AMOUNT1));

        address[] memory tokensToSettle = new address[](1);
        tokensToSettle[0] = address(mockErc20);
        IController.ERC20PermitParams[] memory erc20PermitParamsList;
        IController.ERC721PermitParams[] memory erc721PermitParamsList;

        uint256 beforeBalance = Constants.TAKER1.balance;
        uint256 beforeTokenBalance = mockErc20.balanceOf(Constants.TAKER1);

        vm.startPrank(Constants.TAKER1);
        mockErc20.approve(address(controller), type(uint256).max);
        controller.execute{value: Constants.QUOTE_AMOUNT3}(
            actionList,
            paramsDataList,
            tokensToSettle,
            erc20PermitParamsList,
            erc721PermitParamsList,
            uint64(block.timestamp)
        );
        vm.stopPrank();

        uint256 spentQuoteAmount =
            Tick.wrap(Constants.PRICE_TICK).baseToQuote(Constants.BASE_AMOUNT1, false) / 10 ** 12 * 10 ** 12;
        uint256 quoteAmount = spentQuoteAmount + 152 * 10 ** 18 + 1000000000000 - 94000000000000000000;
        assertEq(Constants.TAKER1.balance - beforeBalance, quoteAmount);
        uint256 spentAmount = Tick.wrap(Constants.PRICE_TICK + 2).quoteToBase(94000000000000000000, true)
            + Tick.wrap(Constants.PRICE_TICK).quoteToBase(152 * 10 ** 18 + 1000000000000 - 94000000000000000000, true)
            + Tick.wrap(Constants.PRICE_TICK).quoteToBase(spentQuoteAmount, true);

        assertEq(beforeTokenBalance - mockErc20.balanceOf(Constants.TAKER1), spentAmount);

        actionList = new IController.Action[](1);
        actionList[0] = IController.Action.CLAIM;

        paramsDataList = new bytes[](1);
        paramsDataList[0] = abi.encode(_claimOrder(orderId1));

        beforeTokenBalance = mockErc20.balanceOf(Constants.MAKER1);

        IController.PermitSignature memory signature;
        erc721PermitParamsList = new IController.ERC721PermitParams[](0);

        vm.startPrank(Constants.MAKER1);
        controller.execute(
            actionList,
            paramsDataList,
            tokensToSettle,
            erc20PermitParamsList,
            erc721PermitParamsList,
            uint64(block.timestamp)
        );
        vm.stopPrank();

        assertEq(
            mockErc20.balanceOf(Constants.MAKER1) - beforeTokenBalance,
            Tick.wrap(Constants.PRICE_TICK).quoteToBase(152 * 10 ** 18 + 1000000000000 - 94000000000000000000, true)
                + Tick.wrap(Constants.PRICE_TICK).quoteToBase(spentQuoteAmount, false)
        );

        actionList[0] = IController.Action.CANCEL;

        paramsDataList[0] = abi.encode(_cancelOrder(orderId1));

        beforeBalance = Constants.MAKER1.balance;

        erc721PermitParamsList = new IController.ERC721PermitParams[](1);
        erc721PermitParamsList[0] =
            IController.ERC721PermitParams({tokenId: OrderId.unwrap(orderId1), signature: signature});

        vm.startPrank(Constants.MAKER1);
        manager.approve(address(controller), OrderId.unwrap(orderId1));
        controller.execute(
            actionList,
            paramsDataList,
            tokensToSettle,
            erc20PermitParamsList,
            erc721PermitParamsList,
            uint64(block.timestamp)
        );
        vm.stopPrank();

        assertEq(
            Constants.MAKER1.balance - beforeBalance,
            94 * 10 ** 18 - (152 * 10 ** 18 + 1000000000000 - 94000000000000000000 + spentQuoteAmount)
        );
    }
}
