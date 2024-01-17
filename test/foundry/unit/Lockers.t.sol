// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import "../../../contracts/libraries/Lockers.sol";

contract LockersTest is Test {
    modifier afterInit() {
        Lockers.initialize();
        _;
    }

    function testInitialize() public {
        Lockers.initialize();
        (uint128 length, uint128 nonzeroDeltaCount) = Lockers.lockData();
        assertEq(length, 0, "LENGTH");
        assertEq(nonzeroDeltaCount, 0, "NONZERO_DELTA_COUNT");

        uint256 slot = Lockers.LOCK_DATA_SLOT;
        uint256 raw;
        assembly {
            raw := sload(slot)
        }
        assertEq(raw, 1, "LOCK_DATA");
    }

    function testPush() public afterInit {
        Lockers.push(address(0x1), address(0x2));
        (uint128 length, uint128 nonzeroDeltaCount) = Lockers.lockData();
        assertEq(length, 1, "LENGTH");
        assertEq(nonzeroDeltaCount, 0, "NONZERO_DELTA_COUNT");

        assertEq(Lockers.getLocker(0), address(0x1), "LOCKER");
        assertEq(Lockers.getLockCaller(0), address(0x2), "LOCK_CALLER");
        assertEq(Lockers.getLocker(1), address(0), "EMPTY_LOCKER");
        assertEq(Lockers.getLockCaller(1), address(0), "EMPTY_LOCK_CALLER");

        assertEq(Lockers.getCurrentLocker(), address(0x1), "CURRENT_LOCKER");
        assertEq(Lockers.getCurrentLockCaller(), address(0x2), "CURRENT_LOCK_CALLER");
    }

    function testPushMultiple(address[2][] memory addresses) public afterInit {
        for (uint256 i; i < addresses.length; ++i) {
            Lockers.push(addresses[i][0], addresses[i][1]);
            (uint128 l, uint128 c) = Lockers.lockData();
            assertEq(l, uint128(i + 1), "LENGTH_DURING");
            assertEq(c, 0, "NONZERO_DELTA_COUNT_DURING");
            assertEq(Lockers.getLocker(i), addresses[i][0], "LOCKER_DURING");
            assertEq(Lockers.getLockCaller(i), addresses[i][1], "LOCK_CALLER_DURING");
            assertEq(Lockers.getCurrentLocker(), addresses[i][0], "CURRENT_LOCKER_DURING");
            assertEq(Lockers.getCurrentLockCaller(), addresses[i][1], "CURRENT_LOCK_CALLER_DURING");
        }
        (uint128 length, uint128 nonzeroDeltaCount) = Lockers.lockData();
        assertEq(length, uint128(addresses.length), "LENGTH_AFTER");
        assertEq(nonzeroDeltaCount, 0, "NONZERO_DELTA_COUNT_AFTER");

        for (uint256 i; i < addresses.length; ++i) {
            assertEq(Lockers.getLocker(i), addresses[i][0], "LOCKER_AFTER");
            assertEq(Lockers.getLockCaller(i), addresses[i][1], "LOCK_CALLER_AFTER");
        }
        assertEq(Lockers.getLocker(addresses.length), address(0), "EMPTY_LOCKER");
        assertEq(Lockers.getLockCaller(addresses.length), address(0), "EMPTY_LOCK_CALLER");

        if (addresses.length > 0) {
            assertEq(Lockers.getCurrentLocker(), addresses[addresses.length - 1][0], "CURRENT_LOCKER_AFTER");
            assertEq(Lockers.getCurrentLockCaller(), addresses[addresses.length - 1][1], "CURRENT_LOCK_CALLER_AFTER");
        } else {
            assertEq(Lockers.getCurrentLocker(), address(0), "CURRENT_LOCKER_AFTER");
            assertEq(Lockers.getCurrentLockCaller(), address(0), "CURRENT_LOCK_CALLER_AFTER");
        }
    }

    function testPop() public afterInit {
        Lockers.push(address(0x1), address(0x2));
        (uint128 length,) = Lockers.lockData();
        assertEq(length, 1);
        Lockers.pop();
        (length,) = Lockers.lockData();
        assertEq(length, 0, "LENGTH");
    }

    function testPopMultiple(address[2][] memory addresses) public afterInit {
        for (uint256 i; i < addresses.length; ++i) {
            Lockers.push(addresses[i][0], addresses[i][1]);
        }
        for (uint256 i; i < addresses.length; ++i) {
            Lockers.pop();
            (uint128 length,) = Lockers.lockData();
            assertEq(length, uint128(addresses.length - i - 1), "LENGTH");
            assertEq(
                Lockers.getLocker(addresses.length - i - 1), addresses[addresses.length - i - 1][0], "LOCKER_DURING"
            );
            assertEq(
                Lockers.getLockCaller(addresses.length - i - 1),
                addresses[addresses.length - i - 1][1],
                "LOCK_CALLER_DURING"
            );
            if (length > 0) {
                assertEq(Lockers.getCurrentLocker(), addresses[addresses.length - i - 2][0], "CURRENT_LOCKER_DURING");
                assertEq(
                    Lockers.getCurrentLockCaller(), addresses[addresses.length - i - 2][1], "CURRENT_LOCK_CALLER_DURING"
                );
            } else {
                assertEq(Lockers.getCurrentLocker(), address(0), "CURRENT_LOCKER_DURING");
                assertEq(Lockers.getCurrentLockCaller(), address(0), "CURRENT_LOCK_CALLER_DURING");
            }
        }
    }

    function testClear() public afterInit {
        Lockers.push(address(0x1), address(0x2));
        Lockers.push(address(0x3), address(0x4));
        Lockers.clear();
        (uint128 length,) = Lockers.lockData();
        assertEq(length, 0, "LENGTH");
        assertEq(Lockers.getLocker(0), address(0x1), "REMAINED_LOCKER_0");
        assertEq(Lockers.getLockCaller(0), address(0x2), "REMAINED_LOCK_CALLER_0");
        assertEq(Lockers.getLocker(1), address(0x3), "REMAINED_LOCKER_1");
        assertEq(Lockers.getLockCaller(1), address(0x4), "REMAINED_LOCK_CALLER_1");
        assertEq(Lockers.getCurrentLocker(), address(0), "CURRENT_LOCKER");
        assertEq(Lockers.getCurrentLockCaller(), address(0), "CURRENT_LOCK_CALLER");
    }

    function testClearMultiple(address[2][] memory addresses) public afterInit {
        for (uint256 i; i < addresses.length; ++i) {
            Lockers.push(addresses[i][0], addresses[i][1]);
        }
        Lockers.clear();
        (uint128 length,) = Lockers.lockData();
        assertEq(length, 0, "LENGTH");
        for (uint256 i; i < addresses.length; ++i) {
            assertEq(Lockers.getLocker(i), addresses[i][0], "REMAINED_LOCKER");
            assertEq(Lockers.getLockCaller(i), addresses[i][1], "REMAINED_LOCK_CALLER");
        }
        assertEq(Lockers.getCurrentLocker(), address(0), "CURRENT_LOCKER");
        assertEq(Lockers.getCurrentLockCaller(), address(0), "CURRENT_LOCK_CALLER");
    }

    function testIncrementNonzeroDeltaCount() public afterInit {
        Lockers.incrementNonzeroDeltaCount();
        (, uint128 nonzeroDeltaCount) = Lockers.lockData();
        assertEq(nonzeroDeltaCount, 1, "NONZERO_DELTA_COUNT");
    }

    function testIncrementNonzeroDeltaCountMultiple(uint8 n) public afterInit {
        for (uint256 i; i < n; ++i) {
            Lockers.incrementNonzeroDeltaCount();
            (, uint128 nonzeroDeltaCount) = Lockers.lockData();
            assertEq(nonzeroDeltaCount, uint128(i + 1), "NONZERO_DELTA_COUNT");
        }
    }

    function testDecrementNonzeroDeltaCount() public afterInit {
        Lockers.incrementNonzeroDeltaCount();
        Lockers.decrementNonzeroDeltaCount();
        (, uint128 nonzeroDeltaCount) = Lockers.lockData();
        assertEq(nonzeroDeltaCount, 0, "NONZERO_DELTA_COUNT");
    }

    function testDecrementNonzeroDeltaCountMultiple(uint8 n) public afterInit {
        for (uint256 i; i < n; ++i) {
            Lockers.incrementNonzeroDeltaCount();
        }
        for (uint256 i; i < n; ++i) {
            Lockers.decrementNonzeroDeltaCount();
            (, uint128 nonzeroDeltaCount) = Lockers.lockData();
            assertEq(nonzeroDeltaCount, uint128(n - i - 1), "NONZERO_DELTA_COUNT");
        }
    }
}
