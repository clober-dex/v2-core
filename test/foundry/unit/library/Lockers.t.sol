// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import "../../mocks/LockersWrapper.sol";

contract LockersTest is Test {
    LockersWrapper public lockers;

    function setUp() public {
        lockers = new LockersWrapper();
    }

    modifier afterInit() {
        lockers.initialize();
        _;
    }

    function testInitialize() public {
        lockers.initialize();
        (uint128 length, uint128 nonzeroDeltaCount) = lockers.lockData();
        assertEq(length, 0, "LENGTH");
        assertEq(nonzeroDeltaCount, 0, "NONZERO_DELTA_COUNT");

        assertEq(lockers.load(Lockers.LOCK_DATA_SLOT), bytes32(1), "LOCK_DATA");
    }

    function testPush() public afterInit {
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

    function testPushMultiple(address[2][] memory addresses) public afterInit {
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

    function testPop() public afterInit {
        lockers.push(address(0x1), address(0x2));
        (uint128 length,) = lockers.lockData();
        assertEq(length, 1);
        lockers.pop();
        (length,) = lockers.lockData();
        assertEq(length, 0, "LENGTH");
    }

    function testPopMultiple(address[2][] memory addresses) public afterInit {
        for (uint256 i; i < addresses.length; ++i) {
            lockers.push(addresses[i][0], addresses[i][1]);
        }
        for (uint256 i; i < addresses.length; ++i) {
            lockers.pop();
            (uint128 length,) = lockers.lockData();
            assertEq(length, uint128(addresses.length - i - 1), "LENGTH");
            assertEq(
                lockers.getLocker(addresses.length - i - 1), addresses[addresses.length - i - 1][0], "LOCKER_DURING"
            );
            assertEq(
                lockers.getLockCaller(addresses.length - i - 1),
                addresses[addresses.length - i - 1][1],
                "LOCK_CALLER_DURING"
            );
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

    function testClear() public afterInit {
        lockers.push(address(0x1), address(0x2));
        lockers.push(address(0x3), address(0x4));
        lockers.clear();
        (uint128 length,) = lockers.lockData();
        assertEq(length, 0, "LENGTH");
        assertEq(lockers.getLocker(0), address(0x1), "REMAINED_LOCKER_0");
        assertEq(lockers.getLockCaller(0), address(0x2), "REMAINED_LOCK_CALLER_0");
        assertEq(lockers.getLocker(1), address(0x3), "REMAINED_LOCKER_1");
        assertEq(lockers.getLockCaller(1), address(0x4), "REMAINED_LOCK_CALLER_1");
        assertEq(lockers.getCurrentLocker(), address(0), "CURRENT_LOCKER");
        assertEq(lockers.getCurrentLockCaller(), address(0), "CURRENT_LOCK_CALLER");
    }

    function testClearMultiple(address[2][] memory addresses) public afterInit {
        for (uint256 i; i < addresses.length; ++i) {
            lockers.push(addresses[i][0], addresses[i][1]);
        }
        lockers.clear();
        (uint128 length,) = lockers.lockData();
        assertEq(length, 0, "LENGTH");
        for (uint256 i; i < addresses.length; ++i) {
            assertEq(lockers.getLocker(i), addresses[i][0], "REMAINED_LOCKER");
            assertEq(lockers.getLockCaller(i), addresses[i][1], "REMAINED_LOCK_CALLER");
        }
        assertEq(lockers.getCurrentLocker(), address(0), "CURRENT_LOCKER");
        assertEq(lockers.getCurrentLockCaller(), address(0), "CURRENT_LOCK_CALLER");
    }

    function testIncrementNonzeroDeltaCount() public afterInit {
        lockers.incrementNonzeroDeltaCount();
        (, uint128 nonzeroDeltaCount) = lockers.lockData();
        assertEq(nonzeroDeltaCount, 1, "NONZERO_DELTA_COUNT");
    }

    function testIncrementNonzeroDeltaCountMultiple(uint8 n) public afterInit {
        for (uint256 i; i < n; ++i) {
            lockers.incrementNonzeroDeltaCount();
            (, uint128 nonzeroDeltaCount) = lockers.lockData();
            assertEq(nonzeroDeltaCount, uint128(i + 1), "NONZERO_DELTA_COUNT");
        }
    }

    function testDecrementNonzeroDeltaCount() public afterInit {
        lockers.incrementNonzeroDeltaCount();
        lockers.decrementNonzeroDeltaCount();
        (, uint128 nonzeroDeltaCount) = lockers.lockData();
        assertEq(nonzeroDeltaCount, 0, "NONZERO_DELTA_COUNT");
    }

    function testDecrementNonzeroDeltaCountMultiple(uint8 n) public afterInit {
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
