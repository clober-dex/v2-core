// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import "../../mocks/LockersWrapper.sol";

contract LockersTest is Test {
    LockersWrapper public lockers;

    function setUp() public {
        lockers = new LockersWrapper();
    }

    function testPush() public {
        lockers.push(address(0x1), address(0x2));
        (uint128 length, uint128 nonzeroDeltaCount) = lockers.lockData();
        assertEq(length, 1, "LENGTH");
        assertEq(nonzeroDeltaCount, 0, "NONZERO_DELTA_COUNT");

        assertEq(lockers.getLocker(0), address(0x1), "LOCKER");
        assertEq(lockers.getLockCaller(0), address(0x2), "LOCK_CALLER");
        assertEq(lockers.getLocker(1), address(0), "EMPTY_LOCKER");
        assertEq(lockers.getLockCaller(1), address(0), "EMPTY_LOCK_CALLER");

        assertEq(lockers.getCurrentLocker(), address(0x1), "CURRENT_LOCKER");
        assertEq(lockers.getCurrentLockCaller(), address(0x2), "CURRENT_LOCK_CALLER");
    }

    function testPushMultiple(address[2][] memory addresses) public {
        for (uint256 i; i < addresses.length; ++i) {
            lockers.push(addresses[i][0], addresses[i][1]);
            (uint128 l, uint128 c) = lockers.lockData();
            assertEq(l, uint128(i + 1), "LENGTH_DURING");
            assertEq(c, 0, "NONZERO_DELTA_COUNT_DURING");
            assertEq(lockers.getLocker(i), addresses[i][0], "LOCKER_DURING");
            assertEq(lockers.getLockCaller(i), addresses[i][1], "LOCK_CALLER_DURING");
            assertEq(lockers.getCurrentLocker(), addresses[i][0], "CURRENT_LOCKER_DURING");
            assertEq(lockers.getCurrentLockCaller(), addresses[i][1], "CURRENT_LOCK_CALLER_DURING");
        }
        (uint128 length, uint128 nonzeroDeltaCount) = lockers.lockData();
        assertEq(length, uint128(addresses.length), "LENGTH_AFTER");
        assertEq(nonzeroDeltaCount, 0, "NONZERO_DELTA_COUNT_AFTER");

        for (uint256 i; i < addresses.length; ++i) {
            assertEq(lockers.getLocker(i), addresses[i][0], "LOCKER_AFTER");
            assertEq(lockers.getLockCaller(i), addresses[i][1], "LOCK_CALLER_AFTER");
        }
        assertEq(lockers.getLocker(addresses.length), address(0), "EMPTY_LOCKER");
        assertEq(lockers.getLockCaller(addresses.length), address(0), "EMPTY_LOCK_CALLER");

        if (addresses.length > 0) {
            assertEq(lockers.getCurrentLocker(), addresses[addresses.length - 1][0], "CURRENT_LOCKER_AFTER");
            assertEq(lockers.getCurrentLockCaller(), addresses[addresses.length - 1][1], "CURRENT_LOCK_CALLER_AFTER");
        } else {
            assertEq(lockers.getCurrentLocker(), address(0), "CURRENT_LOCKER_AFTER");
            assertEq(lockers.getCurrentLockCaller(), address(0), "CURRENT_LOCK_CALLER_AFTER");
        }
    }

    function testPop() public {
        lockers.push(address(0x1), address(0x2));
        (uint128 length,) = lockers.lockData();
        assertEq(length, 1);
        lockers.pop();
        (length,) = lockers.lockData();
        assertEq(length, 0, "LENGTH");
    }

    function testPopMultiple(address[2][] memory addresses) public {
        for (uint256 i; i < addresses.length; ++i) {
            lockers.push(addresses[i][0], addresses[i][1]);
        }
        for (uint256 i; i < addresses.length; ++i) {
            lockers.pop();
            (uint128 length,) = lockers.lockData();
            assertEq(length, uint128(addresses.length - i - 1), "LENGTH");
            assertEq(lockers.getLocker(addresses.length - i - 1), address(0), "LOCKER_DURING");
            assertEq(lockers.getLockCaller(addresses.length - i - 1), address(0), "LOCK_CALLER_DURING");
            if (length > 0) {
                assertEq(lockers.getCurrentLocker(), addresses[addresses.length - i - 2][0], "CURRENT_LOCKER_DURING");
                assertEq(
                    lockers.getCurrentLockCaller(), addresses[addresses.length - i - 2][1], "CURRENT_LOCK_CALLER_DURING"
                );
            } else {
                assertEq(lockers.getCurrentLocker(), address(0), "CURRENT_LOCKER_DURING");
                assertEq(lockers.getCurrentLockCaller(), address(0), "CURRENT_LOCK_CALLER_DURING");
            }
        }
    }

    function testPopFailedWhenLengthIsZero() public {
        vm.expectRevert(abi.encodeWithSignature("LockersPopFailed()"));
        lockers.pop();
    }

    function testIncrementNonzeroDeltaCount() public {
        lockers.incrementNonzeroDeltaCount();
        (, uint128 nonzeroDeltaCount) = lockers.lockData();
        assertEq(nonzeroDeltaCount, 1, "NONZERO_DELTA_COUNT");
    }

    function testIncrementNonzeroDeltaCountMultiple(uint8 n) public {
        for (uint256 i; i < n; ++i) {
            lockers.incrementNonzeroDeltaCount();
            (, uint128 nonzeroDeltaCount) = lockers.lockData();
            assertEq(nonzeroDeltaCount, uint128(i + 1), "NONZERO_DELTA_COUNT");
        }
    }

    function testDecrementNonzeroDeltaCount() public {
        lockers.incrementNonzeroDeltaCount();
        lockers.decrementNonzeroDeltaCount();
        (, uint128 nonzeroDeltaCount) = lockers.lockData();
        assertEq(nonzeroDeltaCount, 0, "NONZERO_DELTA_COUNT");
    }

    function testDecrementNonzeroDeltaCountMultiple(uint8 n) public {
        for (uint256 i; i < n; ++i) {
            lockers.incrementNonzeroDeltaCount();
        }
        for (uint256 i; i < n; ++i) {
            lockers.decrementNonzeroDeltaCount();
            (, uint128 nonzeroDeltaCount) = lockers.lockData();
            assertEq(nonzeroDeltaCount, uint128(n - i - 1), "NONZERO_DELTA_COUNT");
        }
    }
}
