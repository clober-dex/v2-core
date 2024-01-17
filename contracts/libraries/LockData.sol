// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

/// @author Clober
/// @author Modified from Uniswap V4 (https://github.com/Uniswap/v4-core/tree/98680ebc1a654120e995d53a5b10ec6fe153066f)
/// @notice Contains data about pool lockers.
struct LockData {
    /// @notice The current number of active lockers
    uint128 length;
    /// @notice The total number of nonzero deltas over all active + completed lockers
    uint128 nonzeroDeltaCount;
}

/// @dev This library manages a custom storage implementation for a queue
///      that tracks current lockers. The "sentinel" storage slot for this data structure,
///      always passed in as IPoolManager.LockData storage self, stores not just the current
///      length of the queue but also the global count of non-zero deltas across all lockers.
///      The values of the data structure start at OFFSET, and each value is a locker address.
library LockDataLibrary {
    uint256 private constant OFFSET = uint256(keccak256("LockData"));

    // The number of slots per item in the lockers array
    uint256 private constant LOCKER_STRUCT_SIZE = 2;

    /// @dev Pushes a locker onto the end of the queue, and updates the sentinel storage slot.
    function push(LockData storage self, address locker, address lockCaller) internal {
        // read current value from the sentinel storage slot
        uint128 length = self.length;
        unchecked {
            // not in assembly because OFFSET is in the library scope
            uint256 indexToWrite = OFFSET + (length * LOCKER_STRUCT_SIZE);
            /// @solidity memory-safe-assembly
            assembly {
                // in the next storage slot, write the locker and lockCaller
                sstore(indexToWrite, locker)
                sstore(add(indexToWrite, 1), lockCaller)
            }
            // update the sentinel storage slot
            self.length = length + 1;
        }
    }

    /// @dev Pops a locker off the end of the queue. Note that no storage gets cleared.
    function pop(LockData storage self) internal {
        unchecked {
            self.length--;
        }
    }

    function getLocker(uint256 i) internal view returns (address locker) {
        unchecked {
            // not in assembly because OFFSET is in the library scope
            uint256 position = OFFSET + (i * LOCKER_STRUCT_SIZE);
            /// @solidity memory-safe-assembly
            assembly {
                locker := sload(position)
            }
        }
    }

    function getLockCaller(uint256 i) internal view returns (address locker) {
        unchecked {
            // not in assembly because OFFSET is in the library scope
            uint256 position = OFFSET + (i * LOCKER_STRUCT_SIZE + 1);
            /// @solidity memory-safe-assembly
            assembly {
                locker := sload(position)
            }
        }
    }

    function getActiveLocker(LockData storage self) internal view returns (address locker) {
        return getLocker(self.length - 1);
    }
}
