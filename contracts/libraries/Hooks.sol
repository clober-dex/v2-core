// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Lockers} from "./Lockers.sol";
import {IBookManager} from "../interfaces/IBookManager.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {OrderId} from "../libraries/OrderId.sol";

/// @author Clober
/// @author Modified from Uniswap V4 (https://github.com/Uniswap/v4-core/blob/1f350fa95e862ba8c56c8ff7e146d47c9043465e)
/// @notice V4 decides whether to invoke specific hooks by inspecting the leading bits of the address that
/// the hooks contract is deployed to.
/// For example, a hooks contract deployed to address: 0x9000000000000000000000000000000000000000
/// has leading bits '1001' which would cause the 'before open' and 'after make' hooks to be used.
library Hooks {
    using Hooks for IHooks;

    uint256 internal constant BEFORE_OPEN_FLAG = 1 << 159;
    uint256 internal constant AFTER_OPEN_FLAG = 1 << 158;
    uint256 internal constant BEFORE_MAKE_FLAG = 1 << 157;
    uint256 internal constant AFTER_MAKE_FLAG = 1 << 156;
    uint256 internal constant BEFORE_TAKE_FLAG = 1 << 155;
    uint256 internal constant AFTER_TAKE_FLAG = 1 << 154;
    uint256 internal constant BEFORE_CANCEL_FLAG = 1 << 153;
    uint256 internal constant AFTER_CANCEL_FLAG = 1 << 152;
    uint256 internal constant BEFORE_CLAIM_FLAG = 1 << 151;
    uint256 internal constant AFTER_CLAIM_FLAG = 1 << 150;

    struct Permissions {
        bool beforeOpen;
        bool afterOpen;
        bool beforeMake;
        bool afterMake;
        bool beforeTake;
        bool afterTake;
        bool beforeCancel;
        bool afterCancel;
        bool beforeClaim;
        bool afterClaim;
    }

    /// @notice Thrown if the address will not lead to the specified hook calls being called
    /// @param hooks The address of the hooks contract
    error HookAddressNotValid(address hooks);

    /// @notice Hook did not return its selector
    error InvalidHookResponse();

    /// @notice thrown when a hook call fails
    error FailedHookCall();

    /// @notice Utility function intended to be used in hook constructors to ensure
    /// the deployed hooks address causes the intended hooks to be called
    /// @param permissions The hooks that are intended to be called
    /// @dev permissions param is memory as the function will be called from constructors
    function validateHookPermissions(IHooks self, Permissions memory permissions) internal pure {
        if (
            permissions.beforeOpen != self.hasPermission(BEFORE_OPEN_FLAG)
                || permissions.afterOpen != self.hasPermission(AFTER_OPEN_FLAG)
                || permissions.beforeMake != self.hasPermission(BEFORE_MAKE_FLAG)
                || permissions.afterMake != self.hasPermission(AFTER_MAKE_FLAG)
                || permissions.beforeTake != self.hasPermission(BEFORE_TAKE_FLAG)
                || permissions.afterTake != self.hasPermission(AFTER_TAKE_FLAG)
                || permissions.beforeCancel != self.hasPermission(BEFORE_CANCEL_FLAG)
                || permissions.afterCancel != self.hasPermission(AFTER_CANCEL_FLAG)
                || permissions.beforeClaim != self.hasPermission(BEFORE_CLAIM_FLAG)
                || permissions.afterClaim != self.hasPermission(AFTER_CLAIM_FLAG)
        ) {
            revert HookAddressNotValid(address(self));
        }
    }

    /// @notice Ensures that the hook address includes at least one hook flag or is the 0 address
    /// @param hook The hook to verify
    function isValidHookAddress(IHooks hook) internal pure returns (bool) {
        // If a hook contract is set, it must have at least 1 flag set
        return address(hook) == address(0) || uint160(address(hook)) >= AFTER_CLAIM_FLAG;
    }

    /// @notice performs a hook call using the given calldata on the given hook
    /// @return expectedSelector The selector that the hook is expected to return
    /// @return selector The selector that the hook actually returned
    function _callHook(IHooks self, bytes memory data) private returns (bytes4 expectedSelector, bytes4 selector) {
        bool set = Lockers.setCurrentHook(self);

        assembly {
            expectedSelector := mload(add(data, 0x20))
        }

        (bool success, bytes memory result) = address(self).call(data);
        if (!success) _revert(result);

        selector = abi.decode(result, (bytes4));

        // We only want to clear the current hook if it was set in setCurrentHook in this execution frame.
        if (set) Lockers.clearCurrentHook();
    }

    /// @notice performs a hook call using the given calldata on the given hook
    function callHook(IHooks self, bytes memory data) internal {
        (bytes4 expectedSelector, bytes4 selector) = _callHook(self, data);

        if (selector != expectedSelector) revert InvalidHookResponse();
    }

    /// @notice calls beforeOpen hook if permissioned and validates return value
    function beforeOpen(IHooks self, IBookManager.BookKey memory key, bytes calldata hookData) internal {
        if (self.hasPermission(BEFORE_OPEN_FLAG)) {
            self.callHook(abi.encodeWithSelector(IHooks.beforeOpen.selector, msg.sender, key, hookData));
        }
    }

    /// @notice calls afterOpen hook if permissioned and validates return value
    function afterOpen(IHooks self, IBookManager.BookKey memory key, bytes calldata hookData) internal {
        if (self.hasPermission(AFTER_OPEN_FLAG)) {
            self.callHook(abi.encodeWithSelector(IHooks.afterOpen.selector, msg.sender, key, hookData));
        }
    }

    /// @notice calls beforeMake hook if permissioned and validates return value
    function beforeMake(IHooks self, IBookManager.MakeParams memory params, bytes calldata hookData) internal {
        if (self.hasPermission(BEFORE_MAKE_FLAG)) {
            self.callHook(abi.encodeWithSelector(IHooks.beforeMake.selector, msg.sender, params, hookData));
        }
    }

    /// @notice calls afterMake hook if permissioned and validates return value
    function afterMake(IHooks self, IBookManager.MakeParams memory params, OrderId orderId, bytes calldata hookData)
        internal
    {
        if (self.hasPermission(AFTER_MAKE_FLAG)) {
            self.callHook(abi.encodeWithSelector(IHooks.afterMake.selector, msg.sender, params, orderId, hookData));
        }
    }

    /// @notice calls beforeTake hook if permissioned and validates return value
    function beforeTake(IHooks self, IBookManager.TakeParams memory params, bytes calldata hookData) internal {
        if (self.hasPermission(BEFORE_TAKE_FLAG)) {
            self.callHook(abi.encodeWithSelector(IHooks.beforeTake.selector, msg.sender, params, hookData));
        }
    }

    /// @notice calls afterTake hook if permissioned and validates return value
    function afterTake(IHooks self, IBookManager.TakeParams memory params, uint64 takenAmount, bytes calldata hookData)
        internal
    {
        if (self.hasPermission(AFTER_TAKE_FLAG)) {
            self.callHook(abi.encodeWithSelector(IHooks.afterTake.selector, msg.sender, params, takenAmount, hookData));
        }
    }

    /// @notice calls beforeCancel hook if permissioned and validates return value
    function beforeCancel(IHooks self, IBookManager.CancelParams calldata params, bytes calldata hookData) internal {
        if (self.hasPermission(BEFORE_CANCEL_FLAG)) {
            self.callHook(abi.encodeWithSelector(IHooks.beforeCancel.selector, msg.sender, params, hookData));
        }
    }

    /// @notice calls afterCancel hook if permissioned and validates return value
    function afterCancel(
        IHooks self,
        IBookManager.CancelParams calldata params,
        uint64 canceledAmount,
        bytes calldata hookData
    ) internal {
        if (self.hasPermission(AFTER_CANCEL_FLAG)) {
            self.callHook(
                abi.encodeWithSelector(IHooks.afterCancel.selector, msg.sender, params, canceledAmount, hookData)
            );
        }
    }

    /// @notice calls beforeClaim hook if permissioned and validates return value
    function beforeClaim(IHooks self, OrderId orderId, bytes calldata hookData) internal {
        if (self.hasPermission(BEFORE_CLAIM_FLAG)) {
            self.callHook(abi.encodeWithSelector(IHooks.beforeClaim.selector, msg.sender, orderId, hookData));
        }
    }

    /// @notice calls afterClaim hook if permissioned and validates return value
    function afterClaim(IHooks self, OrderId orderId, uint64 claimedAmount, bytes calldata hookData) internal {
        if (self.hasPermission(AFTER_CLAIM_FLAG)) {
            self.callHook(
                abi.encodeWithSelector(IHooks.afterClaim.selector, msg.sender, orderId, claimedAmount, hookData)
            );
        }
    }

    function hasPermission(IHooks self, uint256 flag) internal pure returns (bool) {
        return uint256(uint160(address(self))) & flag != 0;
    }

    /// @notice bubble up revert if present. Else throw FailedHookCall
    function _revert(bytes memory result) private pure {
        if (result.length == 0) revert FailedHookCall();
        assembly {
            revert(add(0x20, result), mload(result))
        }
    }
}
