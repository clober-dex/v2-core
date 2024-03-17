// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {IBookManager} from "../interfaces/IBookManager.sol";

type BookId is uint192;

library BookIdLibrary {
    function toId(IBookManager.BookKey memory bookKey) internal pure returns (BookId id) {
        bytes32 hash = keccak256(abi.encode(bookKey));
        assembly {
            id := hash
        }
    }
}
