// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

import "../interfaces/IBountyPlatform.sol";
import "./BaseHook.sol";

contract BountyPlatform is BaseHook, Ownable2Step, IBountyPlatform {
    using CurrencyLibrary for Currency;
    using OrderIdLibrary for OrderId;
    using BookIdLibrary for IBookManager.BookKey;

    address public override defaultClaimer;

    mapping(Currency => uint256) public override balance;
    mapping(OrderId => Bounty) private _bountyMap;

    constructor(IBookManager bookManager_, address owner_, address defaultClaimer_)
        BaseHook(bookManager_)
        Ownable(owner_)
    {
        defaultClaimer = defaultClaimer_;
        emit SetDefaultClaimer(defaultClaimer_);
    }

    function getHooksCalls() public pure override returns (Hooks.Permissions memory) {
        Hooks.Permissions memory permissions;
        permissions.afterMake = true;
        permissions.afterCancel = true;
        permissions.afterClaim = true;
        return permissions;
    }

    function afterMake(address, IBookManager.MakeParams calldata, OrderId id, bytes calldata hookData)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        if (hookData.length > 0) {
            Bounty memory bounty = abi.decode(hookData, (Bounty));
            uint256 amount = _getAmount(bounty);
            if (amount > 0) {
                if (bounty.currency.balanceOfSelf() < amount) revert NotEnoughBalance();
                balance[bounty.currency] += amount;
                _bountyMap[id] = bounty;
                emit BountyOffered(id, bounty.currency, amount);
            }
        }

        return BaseHook.afterMake.selector;
    }

    function afterClaim(address, OrderId id, uint64 claimedAmount, bytes calldata hookData)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        address claimer = hookData.length > 0 ? abi.decode(hookData, (address)) : defaultClaimer;
        if (claimedAmount > 0 && bookManager.getOrder(id).open == 0) {
            Bounty memory bounty = _bountyMap[id];
            uint256 amount = _getAmount(bounty);
            if (amount > 0) {
                unchecked {
                    balance[bounty.currency] -= amount;
                }
                delete _bountyMap[id];
                bounty.currency.transfer(claimer, amount);
                emit BountyClaimed(id, claimer);
            }
        }
        return BaseHook.afterClaim.selector;
    }

    function afterCancel(address, IBookManager.CancelParams calldata params, uint64, bytes calldata hookData)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        address receiver = hookData.length > 0 ? abi.decode(hookData, (address)) : defaultClaimer;
        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(params.id);
        if (orderInfo.open == 0 && orderInfo.claimable == 0) {
            Bounty memory bounty = _bountyMap[params.id];
            uint256 amount = _getAmount(bounty);
            if (amount > 0) {
                unchecked {
                    balance[bounty.currency] -= amount;
                }
                delete _bountyMap[params.id];
                bounty.currency.transfer(receiver, amount);
                emit BountyCanceled(params.id);
            }
        }
        return BaseHook.afterCancel.selector;
    }

    function _getAmount(Bounty memory bounty) internal pure returns (uint256) {
        return uint256(bounty.amount) << bounty.shifter;
    }

    function getBounty(OrderId orderId) external view returns (Currency, uint256) {
        Bounty memory bounty = _bountyMap[orderId];
        return (bounty.currency, _getAmount(bounty));
    }

    function setDefaultClaimer(address claimer) external onlyOwner {
        defaultClaimer = claimer;
        emit SetDefaultClaimer(claimer);
    }

    receive() external payable {}
}
