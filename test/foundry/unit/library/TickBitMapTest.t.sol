// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../mocks/TickBitMapWrapper.sol";

contract TickBitMapTest is Test {
    uint16 private constant _MAX_HEAP_SIZE = type(uint16).max;

    uint24 private _min;

    TickBitMapWrapper testWrapper;

    function setUp() public {
        testWrapper = new TickBitMapWrapper();
        _min = type(uint24).max;
    }

    function _set(uint24[] memory numbers) private returns (uint24[] memory elements) {
        uint256 length;
        for (uint256 i = 0; i < numbers.length; ++i) {
            uint24 number = numbers[i];
            if (testWrapper.has(number)) continue;
            if (number < _min) _min = number;

            assertFalse(testWrapper.has(number), "BEFORE_PUSH");
            testWrapper.set(number);
            numbers[length] = number;
            length += 1;
            assertTrue(testWrapper.has(number), "AFTER_PUSH");
            assertEq(testWrapper.lowest(), _min, "ASSERT_MIN");
        }

        elements = new uint24[](length);
        for (uint256 i = 0; i < length; ++i) {
            elements[i] = numbers[i];
        }
    }

    function testClear(uint24[] calldata numbers) public {
        vm.assume(1 <= numbers.length && numbers.length <= _MAX_HEAP_SIZE);
        assertTrue(testWrapper.isEmpty(), "HAS_TO_BE_EMPTY");
        uint24[] memory elements = _set(numbers);
        uint256 length = elements.length;

        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (elements[i] > elements[j]) {
                    uint24 temp = elements[j];
                    elements[j] = elements[i];
                    elements[i] = temp;
                }
            }
        }

        for (uint256 i = 0; i < length - 1; i++) {
            console.log(elements[i]);
            console.log(testWrapper.has(1));
            console.log(testWrapper.has(3));
            if (elements[i] > 0) {
                console.log(testWrapper.minGreaterThan(elements[i] - 1));
                assertTrue(testWrapper.minGreaterThan(elements[i] - 1) == elements[i], "WRONG_MIN");
            }
            assertTrue(testWrapper.minGreaterThan(elements[i]) == elements[i + 1], "WRONG_MIN");
        }
        assertTrue(testWrapper.minGreaterThan(elements[length - 1]) == 0, "NO_MORE_MIN_VALUE");

        assertFalse(testWrapper.isEmpty(), "HAS_TO_BE_OCCUPIED");
        while (!testWrapper.isEmpty()) {
            _min = testWrapper.lowest();
            assertTrue(testWrapper.has(_min), "HEAP_HAS_ROOT");
            uint256 min;
            if (length == 1) {
                assertTrue(testWrapper.minGreaterThan(_min) == 0, "NO_MORE_MIN_VALUE");
            } else {
                min = testWrapper.minGreaterThan(_min);
            }
            testWrapper.clear(_min);
            length -= 1;
            if (length > 0) assertTrue(testWrapper.lowest() == min, "WRONG_MIN");

            assertFalse(testWrapper.has(_min), "ROOT_HAS_BEEN_POPPED");
            if (testWrapper.isEmpty()) break;
            assertGt(testWrapper.lowest(), _min, "ROOT_HAS_TO_BE_MIN");
        }
    }

    function testSetExistNumber(uint24 number) public {
        testWrapper.set(number);
        vm.expectRevert(abi.encodeWithSelector(TickBitmap.FlipError.selector));
        testWrapper.set(number);
    }

    function testClearWhenEmpty() public {
        vm.expectRevert(abi.encodeWithSelector(TickBitmap.FlipError.selector));
        testWrapper.clear(0);

        vm.expectRevert(abi.encodeWithSelector(TickBitmap.EmptyError.selector));
        testWrapper.lowest();
    }
}
