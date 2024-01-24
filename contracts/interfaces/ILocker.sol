// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ILocker {
    function lockAcquired(address lockCaller, bytes calldata data) external returns (bytes memory);
}
