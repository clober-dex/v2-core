// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@clober/library/contracts/SegmentedSegmentTree.sol";

import "../interfaces/IBookManager.sol";
import "./Tick.sol";
import "./OrderId.sol";
import "./TotalClaimableMap.sol";
import "./MockHeap.sol";

library Book {
    using Book for State;
    using MockHeap for MockHeap.Core;
    using SegmentedSegmentTree for SegmentedSegmentTree.Core;
    using TotalClaimableMap for mapping(uint24 => uint256);
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;

    error CancelFailed(uint64 maxCancelableAmount);
    error BookAlreadyInitialized();
    error BookNotInitialized();
    error QueueReplaceFailed();
    error TooLargeTakeAmount();

    struct Queue {
        SegmentedSegmentTree.Core tree;
        uint40 index; // index of where the next order would go
    }

    struct State {
        IBookManager.BookKey key;
        mapping(Tick tick => Queue) queues;
        MockHeap.Core heap;
        // four values of totalClaimable are stored in one uint256
        mapping(uint24 groupIndex => uint256) totalClaimableOf;
    }

    uint40 internal constant MAX_ORDER = 2 ** 15; // 32768
    uint256 internal constant MAX_ORDER_M = 2 ** 15 - 1; // % 32768

    function initialize(State storage self, IBookManager.BookKey calldata key) internal {
        if (self.isInitialized()) revert BookAlreadyInitialized();
        self.key = key;
    }

    function isInitialized(State storage self) internal view returns (bool) {
        return self.key.unit != 0;
    }

    function checkInitialized(State storage self) internal view {
        if (!self.isInitialized()) revert BookNotInitialized();
    }

    function depth(State storage self, Tick tick) internal view returns (uint64) {
        return self.queues[tick].tree.total() - self.totalClaimableOf.get(tick);
    }

    function make(
        State storage self,
        mapping(OrderId => IBookManager.Order) storage orders,
        BookId bookId,
        Tick tick,
        uint64 amount
    ) internal returns (uint40 orderIndex) {
        if (!self.heap.has(tick)) self.heap.push(tick);

        Queue storage queue = self.queues[tick];
        orderIndex = queue.index;

        if (orderIndex >= MAX_ORDER) {
            unchecked {
                uint40 staleOrderIndex = orderIndex - MAX_ORDER;
                uint64 stalePendingAmount = orders[OrderIdLibrary.encode(bookId, tick, staleOrderIndex)].pending;
                if (stalePendingAmount > 0) {
                    // If the order is not settled completely, we cannot replace it
                    uint64 claimable = calculateClaimableRawAmount(self, stalePendingAmount, tick, staleOrderIndex);
                    if (claimable != stalePendingAmount) revert QueueReplaceFailed();
                }
            }

            // The stale order is settled completely, so remove it from the totalClaimableOf.
            // We can determine the stale order is claimable.
            uint64 staleOrderedAmount = queue.tree.get(orderIndex & MAX_ORDER_M);
            if (staleOrderedAmount > 0) self.totalClaimableOf.sub(tick, staleOrderedAmount);
        }

        // @dev Assume that orderIndex is always less than type(uint40).max. If not, `make` will revert.
        queue.index = orderIndex + 1;
        queue.tree.update(orderIndex & MAX_ORDER_M, amount);
    }

    function take(State storage self, uint64 takeAmount) internal returns (Tick tick, uint256 baseAmount) {
        tick = self.heap.root();
        uint64 currentDepth = self.depth(tick);
        if (currentDepth < takeAmount) revert TooLargeTakeAmount();

        baseAmount = tick.rawToBase(takeAmount, true);
        self.totalClaimableOf.add(tick, takeAmount);

        self.cleanHeap();
    }

    function cancel(State storage self, Tick tick, uint40 orderIndex, uint64 pending, uint64 claimableRaw, uint64 to)
        internal
        returns (uint64 canceledAmount)
    {
        uint64 afterPending = to + claimableRaw;
        unchecked {
            if (pending < afterPending) revert CancelFailed(pending - claimableRaw);
            canceledAmount = pending - afterPending;

            self.queues[tick].tree.update(
                orderIndex & MAX_ORDER_M, self.queues[tick].tree.get(orderIndex & MAX_ORDER_M) - canceledAmount
            );
        }
        self.cleanHeap();
    }

    function cleanHeap(State storage self) internal {
        while (!self.heap.isEmpty()) {
            if (self.depth(self.heap.root()) == 0) {
                self.heap.pop();
            } else {
                break;
            }
        }
    }

    function calculateClaimableRawAmount(State storage self, uint64 orderAmount, Tick tick, uint40 index)
        internal
        view
        returns (uint64)
    {
        Queue storage queue = self.queues[tick];
        if (index + MAX_ORDER < queue.index) {
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
        uint256 l = queue.index & MAX_ORDER_M;
        uint256 r = (orderIndex + 1) & MAX_ORDER_M;
        rangeRight = (l < r) ? queue.tree.query(l, r) : queue.tree.total() - queue.tree.query(r, l);
    }
}
