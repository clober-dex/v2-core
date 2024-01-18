// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.23;

import "../../../contracts/libraries/Lockers.sol";

contract LockersWrapper {
    function initialize() external {
        Lockers.initialize();
    }

    function push(address locker, address lockCaller) external {
        Lockers.push(locker, lockCaller);
    }

    function lockData() external view returns (uint128, uint128) {
        return Lockers.lockData();
    }

    function pop() external {
        Lockers.pop();
    }

    function clear() external {
        Lockers.clear();
    }

    function getLocker(uint256 index) external view returns (address) {
        return Lockers.getLocker(index);
    }

    function getLockCaller(uint256 index) external view returns (address) {
        return Lockers.getLockCaller(index);
    }

    function getCurrentLocker() external view returns (address) {
        return Lockers.getCurrentLocker();
    }

    function getCurrentLockCaller() external view returns (address) {
        return Lockers.getCurrentLockCaller();
    }

    function incrementNonzeroDeltaCount() external {
        Lockers.incrementNonzeroDeltaCount();
    }

    function decrementNonzeroDeltaCount() external {
        Lockers.decrementNonzeroDeltaCount();
    }

    function load(uint256 slot) external view returns (uint256) {
        uint256 raw;
        assembly {
            raw := sload(slot)
        }
        return raw;
    }
}
