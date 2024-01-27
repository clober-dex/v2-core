// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../interfaces/IHooks.sol";

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
    ///     /// @dev This value starts with 1 to make dirty slot
    ///     uint128 nextLength;
    ///     /// @notice The total number of nonzero deltas over all active + completed lockers
    ///     uint128 nonzeroDeltaCount;
    /// }
    uint256 internal constant LOCK_DATA_SLOT = uint256(keccak256("LockData"));

    uint256 internal constant LOCKERS_SLOT = uint256(keccak256("Lockers"));

    // The number of slots per item in the lockers array
    uint256 internal constant LOCKER_STRUCT_SIZE = 2;

    uint256 internal constant HOOK_ADDRESS_SLOT = uint256(keccak256("HookAddress"));

    uint256 internal constant NONZERO_DELTA_COUNT_OFFSET = 2 ** 128;

    uint256 internal constant EMPTY_ADDRESS_STORAGE = 1 << 255;

    function initialize() internal {
        clear();
        uint256 lockersSlot = LOCKERS_SLOT;
        // @dev To reduce lock sstore gas, we set 5 lockers storages dirty
        assembly {
            for { let i := 0 } lt(i, 5) { i := add(i, 1) } {
                sstore(lockersSlot, EMPTY_ADDRESS_STORAGE)
                sstore(add(lockersSlot, 1), EMPTY_ADDRESS_STORAGE)
                lockersSlot := add(lockersSlot, LOCKER_STRUCT_SIZE)
            }
        }
    }

    /// @dev Pushes a locker onto the end of the queue, and updates the sentinel storage slot.
    function push(address locker, address lockCaller) internal {
        // read current value from the sentinel storage slot
        uint128 l = length();
        unchecked {
            // not in assembly because OFFSET is in the library scope
            uint256 indexToWrite = LOCKERS_SLOT + (l * LOCKER_STRUCT_SIZE);
            uint256 lockDataSlot = LOCK_DATA_SLOT;
            /// @solidity memory-safe-assembly
            assembly {
                // in the next storage slot, write the locker and lockCaller
                sstore(indexToWrite, locker)
                sstore(add(indexToWrite, 1), lockCaller)

                // increase the length
                sstore(lockDataSlot, add(sload(lockDataSlot), 1))
            }
        }
    }

    function lockData() internal view returns (uint128 l, uint128 nonzeroDeltaCount) {
        uint256 slot = LOCK_DATA_SLOT;
        assembly {
            let data := sload(slot)
            l := sub(data, 1)
            nonzeroDeltaCount := shr(128, data)
        }
    }

    function length() internal view returns (uint128 l) {
        uint256 slot = LOCK_DATA_SLOT;
        assembly {
            l := sub(sload(slot), 1)
        }
    }

    /// @dev Pops a locker off the end of the queue. Note that no storage gets cleared.
    function pop() internal {
        uint256 slot = LOCK_DATA_SLOT;
        assembly {
            sstore(slot, sub(sload(slot), 1))
        }
    }

    function clear() internal {
        uint256 slot = LOCK_DATA_SLOT;
        assembly {
            sstore(slot, 1)
        }
    }

    function getLocker(uint256 i) internal view returns (address locker) {
        unchecked {
            // not in assembly because OFFSET is in the library scope
            uint256 position = LOCKERS_SLOT + (i * LOCKER_STRUCT_SIZE);
            /// @solidity memory-safe-assembly
            assembly {
                locker := sload(position)
            }
        }
    }

    function getLockCaller(uint256 i) internal view returns (address locker) {
        unchecked {
            // not in assembly because OFFSET is in the library scope
            uint256 position = LOCKERS_SLOT + (i * LOCKER_STRUCT_SIZE + 1);
            /// @solidity memory-safe-assembly
            assembly {
                locker := sload(position)
            }
        }
    }

    function getCurrentLocker() internal view returns (address) {
        uint128 l = length();
        unchecked {
            return l > 0 ? getLocker(l - 1) : address(0);
        }
    }

    function getCurrentLockCaller() internal view returns (address) {
        uint128 l = length();
        unchecked {
            return l > 0 ? getLockCaller(l - 1) : address(0);
        }
    }

    function incrementNonzeroDeltaCount() internal {
        uint256 slot = LOCK_DATA_SLOT;
        assembly {
            sstore(slot, add(sload(slot), NONZERO_DELTA_COUNT_OFFSET))
        }
    }

    function decrementNonzeroDeltaCount() internal {
        uint256 slot = LOCK_DATA_SLOT;
        assembly {
            sstore(slot, sub(sload(slot), NONZERO_DELTA_COUNT_OFFSET))
        }
    }

    function getCurrentHook() internal view returns (IHooks currentHook) {
        return IHooks(getHook(length()));
    }

    function getHook(uint256 i) internal view returns (address hook) {
        unchecked {
            uint256 position = HOOK_ADDRESS_SLOT + i;
            assembly {
                hook := sload(position)
            }
        }
    }

    function setCurrentHook(IHooks currentHook) internal returns (bool set) {
        // Set the hook address for the current locker if the address is 0.
        // If the address is nonzero, a hook has already been set for this lock, and is not allowed to be updated or cleared at the end of the call.
        if (address(getCurrentHook()) == address(0)) {
            unchecked {
                uint256 indexToWrite = HOOK_ADDRESS_SLOT + length();
                assembly {
                    sstore(indexToWrite, currentHook)
                }
            }
            return true;
        }
    }

    function clearCurrentHook() internal {
        unchecked {
            uint256 indexToWrite = HOOK_ADDRESS_SLOT + length();
            assembly {
                sstore(indexToWrite, EMPTY_ADDRESS_STORAGE)
            }
        }
    }
}
