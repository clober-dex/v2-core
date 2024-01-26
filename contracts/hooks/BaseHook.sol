// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "../interfaces/IHooks.sol";
import "../libraries/Hooks.sol";

/// @author Clober
/// @author Modified from https://github.com/Uniswap/v4-periphery/blob/63d64fcd82bff9ec0bad89730ce28d7ffa8e4225/contracts/BaseHook.sol

abstract contract BaseHook is IHooks {
    error InvalidAccess();
    error HookNotImplemented();

    IBookManager public immutable bookManager;

    constructor(IBookManager _bookManager) {
        bookManager = _bookManager;
        validateHookAddress(this);
    }

    modifier onlyBookManager() {
        if (msg.sender != address(bookManager)) revert InvalidAccess();
        _;
    }

    function getHooksCalls() public pure virtual returns (Hooks.Permissions memory);

    // this function is virtual so that we can override it during testing,
    // which allows us to deploy an implementation to any address
    // and then etch the bytecode into the correct address
    function validateHookAddress(BaseHook _this) internal pure virtual {
        Hooks.validateHookPermissions(_this, getHooksCalls());
    }

    function beforeOpen(address, IBookManager.BookKey calldata, bytes calldata) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterOpen(address, IBookManager.BookKey calldata, bytes calldata) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeMake(address, IBookManager.MakeParams calldata, bytes calldata) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterMake(address, IBookManager.MakeParams calldata, OrderId, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeTake(address, IBookManager.TakeParams calldata, bytes calldata) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterTake(address, IBookManager.TakeParams calldata, Tick, uint64, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeCancel(address, IBookManager.CancelParams calldata, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterCancel(address, IBookManager.CancelParams calldata, uint64, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeClaim(address, OrderId, bytes calldata) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterClaim(address, OrderId, uint64, bytes calldata) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }
}
