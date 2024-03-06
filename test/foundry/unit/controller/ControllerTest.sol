// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../../../contracts/Controller.sol";
import "../../mocks/MockERC20.sol";
import "../../../../contracts/BookViewer.sol";

abstract contract ControllerTest is Test {
    using BookIdLibrary for IBookManager.BookKey;

    IBookManager.BookKey public key;
    IBookManager public manager;
    Controller public controller;
    BookViewer public bookViewer;
    MockERC20 public mockErc20;

    function _makeOrder(int24 tick, uint256 quoteAmount, address maker) internal returns (OrderId id) {
        IController.MakeOrderParams[] memory paramsList = new IController.MakeOrderParams[](1);
        address[] memory tokensToSettle;
        IController.ERC20PermitParams[] memory permitParamsList;
        paramsList[0] =
            IController.MakeOrderParams({id: key.toId(), tick: Tick.wrap(tick), quoteAmount: quoteAmount, hookData: ""});

        vm.prank(maker);
        id = controller.make{value: quoteAmount}(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp))[0];
    }

    function _takeOrder(uint256 quoteAmount, uint256 maxBaseAmount, address taker)
        internal
        returns (uint256 expectedTakeAmount, uint256 expectedBaseAmount)
    {
        IController.TakeOrderParams[] memory paramsList = new IController.TakeOrderParams[](1);
        address[] memory tokensToSettle = new address[](1);
        tokensToSettle[0] = address(mockErc20);
        IController.ERC20PermitParams[] memory permitParamsList;
        paramsList[0] = IController.TakeOrderParams({
            id: key.toId(),
            limitPrice: type(uint256).max,
            quoteAmount: quoteAmount,
            hookData: ""
        });

        (expectedTakeAmount, expectedBaseAmount) = bookViewer.getExpectedInput(paramsList[0]);
        vm.startPrank(taker);
        mockErc20.approve(address(controller), maxBaseAmount);
        controller.take(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp));
        vm.stopPrank();
    }

    function _spendOrder(uint256 baseAmount, address taker)
        internal
        returns (uint256 expectedTakeAmount, uint256 expectedBaseAmount)
    {
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

        (expectedTakeAmount, expectedBaseAmount) = bookViewer.getExpectedOutput(paramsList[0]);
        vm.startPrank(taker);
        mockErc20.approve(address(controller), baseAmount);
        controller.spend(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp));
        vm.stopPrank();
    }

    function _limitOrder(int24 tick, uint256 quoteAmount, address taker, IBookManager.BookKey memory takeBookKey) internal {
        IController.LimitOrderParams[] memory paramsList = new IController.LimitOrderParams[](1);
        address[] memory tokensToSettle = new address[](1);
        tokensToSettle[0] = address(mockErc20);
        IController.ERC20PermitParams[] memory permitParamsList;
        paramsList[0] = IController.LimitOrderParams({
            takeBookId: takeBookKey.toId(),
            makeBookId: key.toId(),
            limitPrice: type(uint256).max,
            tick: Tick.wrap(tick),
            quoteAmount: quoteAmount,
            takeHookData: "",
            makeHookData: ""
        });

        vm.prank(taker);
        controller.limit{value: quoteAmount}(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp));
    }

    function _claimOrder(OrderId id) internal {
        IController.ClaimOrderParams[] memory paramsList = new IController.ClaimOrderParams[](1);
        paramsList[0] = IController.ClaimOrderParams({id: id, hookData: ""});
        address[] memory tokensToSettle = new address[](1);
        tokensToSettle[0] = address(mockErc20);

        IController.ERC721PermitParams[] memory permitParamsList;

        vm.prank(manager.ownerOf(OrderId.unwrap(id)));
        controller.claim(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp));
    }

    function _cancelOrder(OrderId id, uint256 to) internal {
        IController.CancelOrderParams[] memory paramsList = new IController.CancelOrderParams[](1);
        IController.PermitSignature memory signature;
        IController.ERC721PermitParams[] memory permitParamsList = new IController.ERC721PermitParams[](1);
        permitParamsList[0] = IController.ERC721PermitParams({tokenId: OrderId.unwrap(id), signature: signature});
        address[] memory tokensToSettle = new address[](1);
        tokensToSettle[0] = address(mockErc20);

        paramsList[0] = IController.CancelOrderParams({id: id, leftQuoteAmount: to, hookData: ""});

        vm.startPrank(manager.ownerOf(OrderId.unwrap(id)));
        manager.approve(address(controller), OrderId.unwrap(id));
        controller.cancel(paramsList, tokensToSettle, permitParamsList, uint64(block.timestamp));
        vm.stopPrank();
    }
}
