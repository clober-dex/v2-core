// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

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
    uint256 public constant LOCK_DATA_SLOT = uint256(keccak256("LockData"));

    uint256 public constant LOCKERS_SLOT = uint256(keccak256("Lockers"));

    // The number of slots per item in the lockers array
    uint256 public constant LOCKER_STRUCT_SIZE = 2;

    uint256 public constant NONZERO_DELTA_COUNT_OFFSET = 2 ** 128;

    function initialize() internal {
        clear();
    }

    /// @dev Pushes a locker onto the end of the queue, and updates the sentinel storage slot.
    function push(address locker, address lockCaller) internal {
        // read current value from the sentinel storage slot
        (uint128 length,) = lockData();
        unchecked {
            // not in assembly because OFFSET is in the library scope
            uint256 indexToWrite = LOCKERS_SLOT + (length * LOCKER_STRUCT_SIZE);
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

    function lockData() internal view returns (uint128 length, uint128 nonzeroDeltaCount) {
        uint256 slot = LOCK_DATA_SLOT;
        assembly {
            let data := sload(slot)
            length := sub(data, 1)
            nonzeroDeltaCount := shr(128, data)
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
        (uint128 length,) = lockData();
        unchecked {
            return length > 0 ? getLocker(length - 1) : address(0);
        }
    }

    function getCurrentLockCaller() internal view returns (address) {
        (uint128 length,) = lockData();
        unchecked {
            return length > 0 ? getLockCaller(length - 1) : address(0);
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
}
