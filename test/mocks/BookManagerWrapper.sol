// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../src/BookManager.sol";

contract BookManagerWrapper is BookManager {
    using Book for Book.State;

    constructor(
        address owner_,
        address defaultProvider_,
        string memory baseURI_,
        string memory contractURI_,
        string memory name_,
        string memory symbol_
    ) BookManager(owner_, defaultProvider_, baseURI_, contractURI_, name_, symbol_) {}

    function firstSlot() public pure returns (bytes32 slot) {
        assembly {
            slot := baseURI.slot
        }
    }

    function setBaseURI(string memory baseURI_) public {
        baseURI = baseURI_;
    }

    function setContractURI(string memory contractURI_) public {
        contractURI = contractURI_;
    }

    function setCurrencyDelta(address locker, Currency currency, int256 delta) public {
        currencyDelta[locker][currency] = delta;
    }

    function setReservesOf(Currency currency, uint256 reserves) public {
        reservesOf[currency] = reserves;
    }

    function setBookKey(BookId bookId, IBookManager.BookKey calldata key) public {
        _books[bookId].key = key;
    }

    function setWhitelisted(address provider, bool whitelisted) public {
        isWhitelisted[provider] = whitelisted;
    }

    function setTokenOwed(address provider, Currency currency, uint256 owed) public {
        tokenOwed[provider][currency] = owed;
    }

    function pushLockedBy(address locker, address lockCaller) public {
        Lockers.push(locker, lockCaller);
    }

    function forceMake(BookId id, Tick tick, uint64 amount) public {
        _books[id].make(tick, amount, address(0));
    }
}
