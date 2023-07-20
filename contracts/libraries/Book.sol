// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@clober/library/contracts/SegmentedSegmentTree.sol";
import "./Tick.sol";
import "./OrderId.sol";
import "./TotalClaimableMap.sol";
import "../interfaces/IBookManager.sol";

library Book {
    using SegmentedSegmentTree for SegmentedSegmentTree.Core;
    using TotalClaimableMap for mapping(uint24 => uint256);

    error BookAlreadyInitialized();
    error BookNotInitialized();

    uint256 private constant _MAX_ORDER = 2 ** 15; // 32768
    uint256 private constant _MAX_ORDER_M = 2 ** 15 - 1; // % 32768

    struct Queue {
        SegmentedSegmentTree.Core tree;
        uint40 index; // index of where the next order would go
    }

    struct Order {
        uint64 initial;
        address owner;
        uint64 pending; // Unclaimed amount
        uint32 bounty;
        address provider;
    }

    struct State {
        IBookManager.BookKey key;
        mapping(Tick tick => Queue) queues;
        // TODO: add heap
        // four values of totalClaimable are stored in one uint256
        mapping(uint24 groupIndex => uint256) totalClaimableOf;
        mapping(uint256 index => Order) orders;
    }

    function initialize(
        State storage self,
        IBookManager.BookKey calldata key
    ) internal {
        if (self.key.unitDecimals != 0) revert BookAlreadyInitialized();
        self.key = key;
    }

    function depth(State storage self, Tick tick) internal view returns (uint64) {
        return self.queues[tick].tree.total() - self.totalClaimableOf.get(tick);
    }

    function make(
        State storage self,
        BookId bookId,
        address user,
        Tick tick,
        uint64 amount,
        address provider,
        uint32 bounty
    ) internal returns (OrderId id) {
        // TODO: add tick to heap

        Queue storage queue = self.queues[tick];
        uint40 index = queue.index;

        if (index >= _MAX_ORDER) {
            if (self.orders[index - _MAX_ORDER].pending > 0) {
                // TODO: throw queue replace error or claim stale order
            }

            uint64 staleAmount = queue.tree.get(index & _MAX_ORDER_M);
            if (staleAmount > 0) {
                // TODO: clear claimable
            }
        }

        queue.index = index + 1;
        queue.tree.update(index & _MAX_ORDER_M, amount);
        self.orders[index] = Order({
            initial: amount,
            owner: user,
            pending: amount,
            bounty: bounty,
            provider: provider
        });
        return OrderIdLibrary.encode(bookId, tick, index);
    }

    function take(State storage self, uint64 amount) internal {
        // TODO: update totalClaimableOf, add amount
    }

    function spend(State storage self, uint64 amount) internal {
        // TODO: update totalClaimableOf, add amount
    }
}
