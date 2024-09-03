// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {IHooks} from "../interfaces/IHooks.sol";

/// @author Clober
/// @author Modified from Uniswap V4 (https://github.com/Uniswap/v4-core/tree/98680ebc1a654120e995d53a5b10ec6fe153066f)
/// @notice Contains data about pool lockers.

/// @dev This library manages a custom storage implementation for a queue
///      that tracks current lockers. The "sentinel" storage slot for this data structure,
///      always passed in as IPoolManager.LockData storage self, stores not just the current
///      length of the queue but also the global count of non-zero deltas across all lockers.
///      The values of the data structure start at OFFSET, and each value is a locker address.
library Lockers {
    /// struct LockData {
    ///     /// @notice The current number of active lockers
    ///     uint128 length;
    ///     /// @notice The total number of nonzero deltas over all active + completed lockers
    ///     uint128 nonzeroDeltaCount;
    /// }
    // uint256(keccak256("LockData")) + 1
    uint256 internal constant LOCK_DATA_SLOT = 0x760a9a962ae3d184e99c0483cf5684fb3170f47116ca4f445c50209da4f4f907;

    // uint256(keccak256("Lockers")) + 1
    uint256 internal constant LOCKERS_SLOT = 0x722b431450ce53c44434ec138439e45a0639fe031b803ee019b776fae5cfa2b1;

    // The number of slots per item in the lockers array
    uint256 internal constant LOCKER_STRUCT_SIZE = 2;

    // uint256(keccak256("HookAddress")) + 1
    uint256 internal constant HOOK_ADDRESS_SLOT = 0xfcac7593714b88fec0c578a53e9f3f6e4b47eb26c9dcaa7eff23a3ac156be422;

    uint256 internal constant NONZERO_DELTA_COUNT_OFFSET = 2 ** 128;

    uint256 internal constant LENGTH_MASK = (1 << 128) - 1;

    /// @dev Pushes a locker onto the end of the queue, and updates the sentinel storage slot.
    function push(address locker, address lockCaller) internal {
        assembly {
            let data := tload(LOCK_DATA_SLOT)
            let l := and(data, LENGTH_MASK)

            // LOCKERS_SLOT + l * LOCKER_STRUCT_SIZE
            let indexToWrite := add(LOCKERS_SLOT, mul(l, LOCKER_STRUCT_SIZE))

            // in the next storage slot, write the locker and lockCaller
            tstore(indexToWrite, locker)
            tstore(add(indexToWrite, 1), lockCaller)

            // increase the length
            tstore(LOCK_DATA_SLOT, add(data, 1))
        }
    }

    function lockData() internal view returns (uint128 l, uint128 nonzeroDeltaCount) {
        assembly {
            let data := tload(LOCK_DATA_SLOT)
            l := and(data, LENGTH_MASK)
            nonzeroDeltaCount := shr(128, data)
        }
    }

    function length() internal view returns (uint128 l) {
        assembly {
            l := and(tload(LOCK_DATA_SLOT), LENGTH_MASK)
        }
    }

    /// @dev Pops a locker off the end of the queue. Note that no storage gets cleared.
    function pop() internal {
        assembly {
            let data := tload(LOCK_DATA_SLOT)
            let l := and(data, LENGTH_MASK)
            if iszero(l) {
                mstore(0x00, 0xf1c77ed0) // LockersPopFailed()
                revert(0x1c, 0x04)
            }

            // LOCKERS_SLOT + (l - 1) * LOCKER_STRUCT_SIZE
            let indexToWrite := add(LOCKERS_SLOT, mul(sub(l, 1), LOCKER_STRUCT_SIZE))

            // in the next storage slot, delete the locker and lockCaller
            tstore(indexToWrite, 0)
            tstore(add(indexToWrite, 1), 0)

            // decrease the length
            tstore(LOCK_DATA_SLOT, sub(data, 1))
        }
    }

    function getLocker(uint256 i) internal view returns (address locker) {
        assembly {
            // LOCKERS_SLOT + (i * LOCKER_STRUCT_SIZE)
            locker := tload(add(LOCKERS_SLOT, mul(i, LOCKER_STRUCT_SIZE)))
        }
    }

    function getLockCaller(uint256 i) internal view returns (address locker) {
        assembly {
            // LOCKERS_SLOT + (i * LOCKER_STRUCT_SIZE + 1)
            locker := tload(add(LOCKERS_SLOT, add(mul(i, LOCKER_STRUCT_SIZE), 1)))
        }
    }

    function getCurrentLocker() internal view returns (address) {
        unchecked {
            uint256 l = length();
            return l > 0 ? getLocker(l - 1) : address(0);
        }
    }

    function getCurrentLockCaller() internal view returns (address) {
        unchecked {
            uint256 l = length();
            return l > 0 ? getLockCaller(l - 1) : address(0);
        }
    }

    function incrementNonzeroDeltaCount() internal {
        assembly {
            tstore(LOCK_DATA_SLOT, add(tload(LOCK_DATA_SLOT), NONZERO_DELTA_COUNT_OFFSET))
        }
    }

    function decrementNonzeroDeltaCount() internal {
        assembly {
            tstore(LOCK_DATA_SLOT, sub(tload(LOCK_DATA_SLOT), NONZERO_DELTA_COUNT_OFFSET))
        }
    }

    function getCurrentHook() internal view returns (IHooks currentHook) {
        return IHooks(getHook(length()));
    }

    function getHook(uint256 i) internal view returns (address hook) {
        assembly {
            hook := tload(add(HOOK_ADDRESS_SLOT, i))
        }
    }

    function setCurrentHook(IHooks currentHook) internal returns (bool set) {
        // Set the hook address for the current locker if the address is 0.
        // If the address is nonzero, a hook has already been set for this lock, and is not allowed to be updated or cleared at the end of the call.
        if (address(getCurrentHook()) == address(0)) {
            uint256 l = length();
            assembly {
                tstore(add(HOOK_ADDRESS_SLOT, l), currentHook)
            }
            return true;
        }
    }

    function clearCurrentHook() internal {
        uint256 l = length();
        assembly {
            tstore(add(HOOK_ADDRESS_SLOT, l), 0)
        }
    }
}
