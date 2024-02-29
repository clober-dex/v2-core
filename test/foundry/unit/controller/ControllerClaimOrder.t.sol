// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./ControllerTest.sol";
import "../../Constants.sol";
import "../../../../contracts/libraries/BookId.sol";
import "../../../../contracts/libraries/Hooks.sol";
import "../../../../contracts/Controller.sol";
import "../../../../contracts/BookManager.sol";
import "../../mocks/MockERC20.sol";

contract ControllerClaimOrderTest is ControllerTest {
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;
    using Hooks for IHooks;

    IBookManager.BookKey public unopenedKey;
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

        orderId1 = _makeOrder(Constants.PRICE_TICK, Constants.QUOTE_AMOUNT2, Constants.MAKER1);
        orderId2 = _makeOrder(Constants.PRICE_TICK + 1, Constants.QUOTE_AMOUNT1, Constants.MAKER2);

        vm.prank(Constants.MAKER1);
        manager.setApprovalForAll(address(controller), true);

        vm.prank(Constants.MAKER2);
        manager.setApprovalForAll(address(controller), true);

        _takeOrder(Constants.QUOTE_AMOUNT1, type(uint256).max, Constants.TAKER1);
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
