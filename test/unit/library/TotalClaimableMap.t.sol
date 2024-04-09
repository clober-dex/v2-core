// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import "../../mocks/TotalClaimableMapWrapper.sol";

contract TotalClaimableMapTest is Test {
    TotalClaimableMapWrapper public map;

    function setUp() public {
        map = new TotalClaimableMapWrapper();
    }

    function testAdd() public {
        map.add(Tick.wrap(type(int24).max), 412443);
        map.add(Tick.wrap(102), 202);
        map.add(Tick.wrap(101), 201);
        map.add(Tick.wrap(100), type(uint64).max - 1);
        map.add(Tick.wrap(1), 321);
        map.add(Tick.wrap(0), 123);
        map.add(Tick.wrap(-1), 111);
        map.add(Tick.wrap(-420), 0);
        map.add(Tick.wrap(-421), 523);
        map.add(Tick.wrap(type(int24).min), 412443);

        assertEq(map.get(Tick.wrap(type(int24).max)), 412443);
        assertEq(map.get(Tick.wrap(102)), 202);
        assertEq(map.get(Tick.wrap(101)), 201);
        assertEq(map.get(Tick.wrap(100)), type(uint64).max - 1);
        assertEq(map.get(Tick.wrap(1)), 321);
        assertEq(map.get(Tick.wrap(0)), 123);
        assertEq(map.get(Tick.wrap(-1)), 111);
        assertEq(map.get(Tick.wrap(-420)), 0);
        assertEq(map.get(Tick.wrap(-421)), 523);
        assertEq(map.get(Tick.wrap(type(int24).min)), 412443);
    }

    function testAddRevertWithLargeNumber() public {
        vm.expectRevert(abi.encodeWithSelector(DirtyUint64.DirtyUint64Error.selector, 0));
        map.add(Tick.wrap(123), type(uint64).max);
    }

    function testAddMultiple(Tick tick, uint56[10] memory nList) public {
        uint256 sum = 0;
        for (uint256 i = 0; i < nList.length; i++) {
            map.add(tick, nList[i]);
            sum += nList[i];
        }
        assertEq(map.get(tick), sum);
    }

    function testSub() public {
        map.add(Tick.wrap(type(int24).max), 412443);
        map.add(Tick.wrap(102), 202);
        map.add(Tick.wrap(101), 201);
        map.add(Tick.wrap(100), type(uint64).max - 1);
        map.add(Tick.wrap(1), 321);
        map.add(Tick.wrap(0), 123);
        map.add(Tick.wrap(-1), 111);
        map.add(Tick.wrap(-420), 0);
        map.add(Tick.wrap(-421), 523);
        map.add(Tick.wrap(type(int24).min), 412443);

        map.sub(Tick.wrap(type(int24).max), 412443);
        map.sub(Tick.wrap(102), 202);
        map.sub(Tick.wrap(101), 201);
        map.sub(Tick.wrap(100), type(uint64).max - 1);
        map.sub(Tick.wrap(1), 321);
        map.sub(Tick.wrap(0), 123);
        map.sub(Tick.wrap(-1), 111);
        map.sub(Tick.wrap(-420), 0);
        map.sub(Tick.wrap(-421), 523);
        map.sub(Tick.wrap(type(int24).min), 412443);

        assertEq(map.get(Tick.wrap(type(int24).max)), 0);
        assertEq(map.get(Tick.wrap(102)), 0);
        assertEq(map.get(Tick.wrap(101)), 0);
        assertEq(map.get(Tick.wrap(100)), 0);
        assertEq(map.get(Tick.wrap(1)), 0);
        assertEq(map.get(Tick.wrap(0)), 0);
        assertEq(map.get(Tick.wrap(-1)), 0);
        assertEq(map.get(Tick.wrap(-420)), 0);
        assertEq(map.get(Tick.wrap(-421)), 0);
        assertEq(map.get(Tick.wrap(type(int24).min)), 0);
    }

    function testSubMultiple(Tick tick, uint56[10] memory nList) public {
        uint64 sum = 0;
        for (uint256 i = 0; i < nList.length; i++) {
            sum += nList[i];
        }
        map.add(tick, sum);
        for (uint256 i = 0; i < nList.length; i++) {
            map.sub(tick, nList[i]);
            assertEq(map.get(tick), sum - nList[i]);
            sum -= nList[i];
        }
    }
}
