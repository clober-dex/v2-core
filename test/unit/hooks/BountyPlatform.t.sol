// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../src/hooks/BountyPlatform.sol";
import "../../mocks/BountyPlatformWrapper.sol";

contract BountyPlatformTest is Test {
    address public constant DEFAULT_CLAIMER = address(0x1312);
    address public constant CLAIMER = address(0x13423);
    address public constant CANCELER = address(0x423123);

    BountyPlatformWrapper public bountyPlatform = BountyPlatformWrapper(
        payable(address(uint160(Hooks.AFTER_MAKE_FLAG | Hooks.AFTER_CANCEL_FLAG | Hooks.AFTER_CLAIM_FLAG)))
    );

    IBookManager.OrderInfo public mockOrderInfo;
    IBookManager.MakeParams public emptyMakeParams;

    function setUp() public {
        vm.record();
        BountyPlatformWrapper impl =
            new BountyPlatformWrapper(IBookManager(address(this)), address(this), DEFAULT_CLAIMER, bountyPlatform);
        (, bytes32[] memory writes) = vm.accesses(address(impl));
        vm.etch(address(bountyPlatform), address(impl).code);
        // for each storage key that was written during the hook implementation, copy the value over
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(address(bountyPlatform), slot, vm.load(address(impl), slot));
            }
        }
        vm.deal(address(this), 100 ether);
    }

    function getOrder(OrderId) external view returns (IBookManager.OrderInfo memory) {
        return mockOrderInfo;
    }

    function testAfterMake() public {
        OrderId id = OrderId.wrap(0x1234);
        IBountyPlatform.Bounty memory bounty =
            IBountyPlatform.Bounty({currency: CurrencyLibrary.NATIVE, amount: 3000, shifter: 2});
        payable(address(bountyPlatform)).transfer(1 ether);

        vm.expectEmit(address(bountyPlatform));
        emit IBountyPlatform.BountyOffered(id, CurrencyLibrary.NATIVE, 3000 << 2);
        bytes4 ret = bountyPlatform.afterMake(address(this), emptyMakeParams, id, abi.encode(bounty));
        assertEq(ret, BaseHook.afterMake.selector, "RETURN");

        (Currency bountyCurrency, uint256 bountyAmount) = bountyPlatform.getBounty(id);

        assertEq(bountyPlatform.balance(CurrencyLibrary.NATIVE), 3000 << 2, "BALANCE");
        assertEq(Currency.unwrap(bountyCurrency), Currency.unwrap(CurrencyLibrary.NATIVE), "BOUNTY_CURRENCY");
        assertEq(bountyAmount, 3000 << 2, "BOUNTY_AMOUNT");
    }

    function testAfterMakeWhenCurrencyNotEnough() public {
        OrderId id = OrderId.wrap(0x1234);
        IBountyPlatform.Bounty memory bounty =
            IBountyPlatform.Bounty({currency: CurrencyLibrary.NATIVE, amount: 3000, shifter: 2});

        vm.expectRevert(abi.encodeWithSelector(IBountyPlatform.NotEnoughBalance.selector));
        bountyPlatform.afterMake(address(this), emptyMakeParams, id, abi.encode(bounty));
    }

    function testAfterMakeWhenHookDataIsEmpty() public {
        OrderId id = OrderId.wrap(0x1234);
        payable(address(bountyPlatform)).transfer(1 ether);

        bytes4 ret = bountyPlatform.afterMake(address(this), emptyMakeParams, id, "");
        assertEq(ret, BaseHook.afterMake.selector, "RETURN");

        (, uint256 bountyAmount) = bountyPlatform.getBounty(id);

        assertEq(bountyAmount, 0, "BOUNTY_AMOUNT");
    }

    function testAfterMakeWhenBountyAmountIsZero() public {
        OrderId id = OrderId.wrap(0x1234);
        IBountyPlatform.Bounty memory bounty =
            IBountyPlatform.Bounty({currency: CurrencyLibrary.NATIVE, amount: 0, shifter: 2});
        payable(address(bountyPlatform)).transfer(1 ether);

        bytes4 ret = bountyPlatform.afterMake(address(this), emptyMakeParams, id, abi.encode(bounty));
        assertEq(ret, BaseHook.afterMake.selector, "RETURN");

        (, uint256 bountyAmount) = bountyPlatform.getBounty(id);

        assertEq(bountyAmount, 0, "BOUNTY_AMOUNT");
    }

    function _offer() internal returns (OrderId id, uint256 bountyAmount) {
        id = OrderId.wrap(0x1234);
        IBountyPlatform.Bounty memory bounty =
            IBountyPlatform.Bounty({currency: CurrencyLibrary.NATIVE, amount: 3000, shifter: 2});
        bountyAmount = 3000 << 2;
        payable(address(bountyPlatform)).transfer(bountyAmount);

        bountyPlatform.afterMake(address(this), emptyMakeParams, id, abi.encode(bounty));
    }

    function testAfterClaim() public {
        (OrderId id, uint256 bountyAmount) = _offer();

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeClaimerBalance = address(CLAIMER).balance;

        vm.expectEmit(address(bountyPlatform));
        emit IBountyPlatform.BountyClaimed(id, CLAIMER);
        bytes4 ret = bountyPlatform.afterClaim(address(this), id, 1000, abi.encode(CLAIMER));
        assertEq(ret, BaseHook.afterClaim.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(
            bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance - bountyAmount, "PLATFORM_BALANCE"
        );
        assertEq(address(CLAIMER).balance, beforeClaimerBalance + bountyAmount, "CLAIMER_BALANCE");
        assertEq(afterBountyAmount, 0, "BOUNTY_AMOUNT");
    }

    function testAfterClaimWithZeroClaimedAmount() public {
        (OrderId id, uint256 bountyAmount) = _offer();

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeClaimerBalance = address(CLAIMER).balance;

        bytes4 ret = bountyPlatform.afterClaim(address(this), id, 0, abi.encode(CLAIMER));
        assertEq(ret, BaseHook.afterClaim.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance, "PLATFORM_BALANCE");
        assertEq(address(CLAIMER).balance, beforeClaimerBalance, "CLAIMER_BALANCE");
        assertEq(afterBountyAmount, bountyAmount, "BOUNTY_AMOUNT");
    }

    function testAfterClaimWhenOrderAmountLeft() public {
        (OrderId id, uint256 bountyAmount) = _offer();

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeClaimerBalance = address(CLAIMER).balance;
        mockOrderInfo.open = 1000;

        bytes4 ret = bountyPlatform.afterClaim(address(this), id, 1000, abi.encode(CLAIMER));
        assertEq(ret, BaseHook.afterClaim.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance, "PLATFORM_BALANCE");
        assertEq(address(CLAIMER).balance, beforeClaimerBalance, "CLAIMER_BALANCE");
        assertEq(afterBountyAmount, bountyAmount, "BOUNTY_AMOUNT");
    }

    function testAfterClaimWhenOfferedBountyAmountIsZero() public {
        OrderId id = OrderId.wrap(0x1234);
        IBountyPlatform.Bounty memory bounty =
            IBountyPlatform.Bounty({currency: CurrencyLibrary.NATIVE, amount: 0, shifter: 2});
        uint256 bountyAmount = 3000 << 2;
        payable(address(bountyPlatform)).transfer(bountyAmount);

        bountyPlatform.afterMake(address(this), emptyMakeParams, id, abi.encode(bounty));

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeClaimerBalance = address(CLAIMER).balance;

        bytes4 ret = bountyPlatform.afterClaim(address(this), id, 1000, abi.encode(CLAIMER));
        assertEq(ret, BaseHook.afterClaim.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance, "PLATFORM_BALANCE");
        assertEq(address(CLAIMER).balance, beforeClaimerBalance, "CLAIMER_BALANCE");
        assertEq(afterBountyAmount, 0, "BOUNTY_AMOUNT");
    }

    function testAfterClaimWhenHookDataIsEmpty() public {
        (OrderId id, uint256 bountyAmount) = _offer();

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeClaimerBalance = address(CLAIMER).balance;
        uint256 beforeDefaultClaimerBalance = address(DEFAULT_CLAIMER).balance;

        vm.expectEmit(address(bountyPlatform));
        emit IBountyPlatform.BountyClaimed(id, DEFAULT_CLAIMER);
        bytes4 ret = bountyPlatform.afterClaim(address(this), id, 1000, "");
        assertEq(ret, BaseHook.afterClaim.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(
            bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance - bountyAmount, "PLATFORM_BALANCE"
        );
        assertEq(address(CLAIMER).balance, beforeClaimerBalance, "CLAIMER_BALANCE");
        assertEq(
            address(DEFAULT_CLAIMER).balance, beforeDefaultClaimerBalance + bountyAmount, "DEFAULT_CLAIMER_BALANCE"
        );
        assertEq(afterBountyAmount, 0, "BOUNTY_AMOUNT");
    }

    function testAfterCancel() public {
        (OrderId id, uint256 bountyAmount) = _offer();

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeCancelerBalance = address(CANCELER).balance;

        vm.expectEmit(address(bountyPlatform));
        emit IBountyPlatform.BountyCanceled(id);
        bytes4 ret = bountyPlatform.afterCancel(
            address(this), IBookManager.CancelParams({id: id, toUnit: 0}), 1000, abi.encode(address(CANCELER))
        );
        assertEq(ret, BaseHook.afterCancel.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(
            bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance - bountyAmount, "PLATFORM_BALANCE"
        );
        assertEq(address(CANCELER).balance, beforeCancelerBalance + bountyAmount, "CANCELER_BALANCE");
        assertEq(afterBountyAmount, 0, "BOUNTY_AMOUNT");
    }

    function testAfterCancelWhenOrderAmountLeft() public {
        (OrderId id, uint256 bountyAmount) = _offer();

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeCancelerBalance = address(CANCELER).balance;
        mockOrderInfo.open = 1000;

        bytes4 ret = bountyPlatform.afterCancel(
            address(this), IBookManager.CancelParams({id: id, toUnit: 0}), 1000, abi.encode(CANCELER)
        );
        assertEq(ret, BaseHook.afterCancel.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance, "PLATFORM_BALANCE");
        assertEq(address(CANCELER).balance, beforeCancelerBalance, "CLAIMER_BALANCE");
        assertEq(afterBountyAmount, bountyAmount, "BOUNTY_AMOUNT");
    }

    function testAfterCancelWhenClaimableLeft() public {
        (OrderId id, uint256 bountyAmount) = _offer();

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeCancelerBalance = address(CANCELER).balance;
        mockOrderInfo.claimable = 1000;

        bytes4 ret = bountyPlatform.afterCancel(
            address(this), IBookManager.CancelParams({id: id, toUnit: 0}), 1000, abi.encode(CANCELER)
        );
        assertEq(ret, BaseHook.afterCancel.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance, "PLATFORM_BALANCE");
        assertEq(address(CANCELER).balance, beforeCancelerBalance, "CLAIMER_BALANCE");
        assertEq(afterBountyAmount, bountyAmount, "BOUNTY_AMOUNT");
    }

    function testAfterCancelWhenOfferedBountyAmountIsZero() public {
        OrderId id = OrderId.wrap(0x1234);
        IBountyPlatform.Bounty memory bounty =
            IBountyPlatform.Bounty({currency: CurrencyLibrary.NATIVE, amount: 0, shifter: 2});
        uint256 bountyAmount = 3000 << 2;
        payable(address(bountyPlatform)).transfer(bountyAmount);

        bountyPlatform.afterMake(address(this), emptyMakeParams, id, abi.encode(bounty));

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeCancelerBalance = address(CANCELER).balance;

        bytes4 ret = bountyPlatform.afterCancel(
            address(this), IBookManager.CancelParams({id: id, toUnit: 0}), 1000, abi.encode(CANCELER)
        );
        assertEq(ret, BaseHook.afterCancel.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance, "PLATFORM_BALANCE");
        assertEq(address(CANCELER).balance, beforeCancelerBalance, "CLAIMER_BALANCE");
        assertEq(afterBountyAmount, 0, "BOUNTY_AMOUNT");
    }

    function testAfterCancelWhenHookDataIsEmpty() public {
        (OrderId id, uint256 bountyAmount) = _offer();

        uint256 beforePlatformBalance = bountyPlatform.balance(CurrencyLibrary.NATIVE);
        uint256 beforeDefaultClaimerBalance = address(DEFAULT_CLAIMER).balance;

        vm.expectEmit(address(bountyPlatform));
        emit IBountyPlatform.BountyCanceled(id);
        bytes4 ret = bountyPlatform.afterCancel(address(this), IBookManager.CancelParams({id: id, toUnit: 0}), 1000, "");
        assertEq(ret, BaseHook.afterCancel.selector, "RETURN");

        (, uint256 afterBountyAmount) = bountyPlatform.getBounty(id);

        assertEq(
            bountyPlatform.balance(CurrencyLibrary.NATIVE), beforePlatformBalance - bountyAmount, "PLATFORM_BALANCE"
        );
        assertEq(
            address(DEFAULT_CLAIMER).balance, beforeDefaultClaimerBalance + bountyAmount, "DEFAULT_CLAIMER_BALANCE"
        );
        assertEq(afterBountyAmount, 0, "BOUNTY_AMOUNT");
    }

    function testSetDefaultClaimer() public {
        vm.expectEmit(address(bountyPlatform));
        emit IBountyPlatform.SetDefaultClaimer(CLAIMER);
        bountyPlatform.setDefaultClaimer(CLAIMER);
        assertEq(bountyPlatform.defaultClaimer(), CLAIMER, "DEFAULT_CLAIMER");
    }

    function testSetDefaultClaimerOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x1231)));
        vm.prank(address(0x1231));
        bountyPlatform.setDefaultClaimer(CLAIMER);
    }
}
