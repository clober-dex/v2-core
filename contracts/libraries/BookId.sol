// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/IBookManager.sol";

type BookId is bytes32;

library BookIdLibrary {
    function toId(IBookManager.BookKey memory bookKey) internal pure returns (BookId) {
        return BookId.wrap(keccak256(abi.encode(bookKey)));
    }
}
