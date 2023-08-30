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
    error QueueReplaceFailed();

    uint256 private constant _CLAIM_BOUNTY_UNIT = 1 gwei;
    uint40 private constant _MAX_ORDER = 2 ** 15; // 32768
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
        mapping(OrderId => Order) orders;
    }

    function initialize(State storage self, IBookManager.BookKey calldata key) internal {
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
    ) internal returns (OrderId id, Order memory order) {
        // TODO: add tick to heap

        Queue storage queue = self.queues[tick];
        uint40 index = queue.index;

        if (index >= _MAX_ORDER) {
            {
                uint40 staleOrderIndex;
                unchecked {
                    staleOrderIndex = index - _MAX_ORDER;
                }
                uint64 stalePendingAmount = self.orders[OrderIdLibrary.encode(bookId, tick, staleOrderIndex)].pending;
                if (stalePendingAmount > 0) {
                    // If the order is not settled completely, we cannot replace it
                    uint64 claimable = _calculateClaimableRawAmount(self, stalePendingAmount, tick, staleOrderIndex);
                    if (claimable != stalePendingAmount) {
                        revert QueueReplaceFailed();
                    }
                }
            }

            // The stale order is settled completely, so remove it from the totalClaimableOf.
            // We can determine the stale order is claimable.
            uint64 staleOrderedAmount = queue.tree.get(index & _MAX_ORDER_M);
            if (staleOrderedAmount > 0) {
                self.totalClaimableOf.sub(tick, staleOrderedAmount);
            }
        }

        queue.index = index + 1;
        queue.tree.update(index & _MAX_ORDER_M, amount);
        id = OrderIdLibrary.encode(bookId, tick, index);
        order = Order({initial: amount, owner: user, pending: amount, bounty: bounty, provider: provider});
        self.orders[id] = order;
    }

    function take(State storage self, uint64 amount) internal {
        // TODO: update totalClaimableOf, add amount
    }

    function spend(State storage self, uint64 amount) internal {
        // TODO: update totalClaimableOf, add amount
    }

    function _calculateClaimableRawAmount(State storage self, uint64 orderAmount, Tick tick, uint40 index)
        private
        view
        returns (uint64)
    {
        Queue storage queue = self.queues[tick];
        if (index + _MAX_ORDER < queue.index) {
            // replace order
            return orderAmount;
        }
        uint64 totalClaimable = self.totalClaimableOf.get(tick);
        uint64 rangeRight = _getClaimRangeRight(queue, index);
        if (rangeRight >= totalClaimable + orderAmount) return 0;
        if (rangeRight <= totalClaimable) {
            // -------- totalClaimable ---------|---
            // ------|---- orderAmount ----|--------
            //   rangeLeft           rangeRight
            return orderAmount;
        } else {
            // -- totalClaimable --|----------------
            // ------|---- orderAmount ----|--------
            //   rangeLeft           rangeRight
            return totalClaimable + orderAmount - rangeRight;
        }
    }

    function _getClaimRangeRight(Queue storage queue, uint256 orderIndex) private view returns (uint64 rangeRight) {
        uint256 l = queue.index & _MAX_ORDER_M;
        uint256 r = (orderIndex + 1) & _MAX_ORDER_M;
        rangeRight = (l < r) ? queue.tree.query(l, r) : queue.tree.total() - queue.tree.query(r, l);
    }
}
