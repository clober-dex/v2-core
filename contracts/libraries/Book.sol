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

    error BookAlreadyOpened();
    error BookNotOpened();
    error QueueReplaceFailed();
    error TooLargeTakeAmount();
    error CancelFailed(uint64 maxCancelableAmount);

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

    function open(State storage self, IBookManager.BookKey calldata key) internal {
        if (self.isOpened()) revert BookAlreadyOpened();
        self.key = key;
    }

    function isOpened(State storage self) internal view returns (bool) {
        return self.key.unit != 0;
    }

    function checkOpened(State storage self) internal view {
        if (!self.isOpened()) revert BookNotOpened();
    }

    function depth(State storage self, Tick tick) internal view returns (uint64) {
        return self.queues[tick].tree.total() - self.totalClaimableOf.get(tick);
    }

    function root(State storage self) internal view returns (Tick) {
        return self.heap.root();
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

    /**
     * @notice Take orders from the book
     * @param self The book state
     * @param maxTakeAmount The maximum amount to take
     * @return tick The tick of the order
     * @return takeAmount The actual amount to take
     */
    function take(State storage self, uint64 maxTakeAmount) internal returns (Tick tick, uint64 takeAmount) {
        tick = self.heap.root();
        uint64 currentDepth = depth(self, tick);
        takeAmount = currentDepth < maxTakeAmount ? currentDepth : maxTakeAmount;

        self.totalClaimableOf.add(tick, takeAmount);

        self.cleanHeap();
    }

    function cancel(State storage self, OrderId orderId, IBookManager.Order storage order, uint64 to)
        internal
        returns (uint64 canceledAmount)
    {
        (, Tick tick, uint40 orderIndex) = orderId.decode();
        uint64 pending = order.pending;
        uint64 claimableRaw = calculateClaimableRawAmount(self, pending, tick, orderIndex);
        uint64 afterPending = to + claimableRaw;
        unchecked {
            if (pending < afterPending) revert CancelFailed(pending - claimableRaw);
            canceledAmount = pending - afterPending;

            self.queues[tick].tree.update(
                orderIndex & MAX_ORDER_M, self.queues[tick].tree.get(orderIndex & MAX_ORDER_M) - canceledAmount
            );
        }
        order.pending = afterPending;

        self.cleanHeap();
    }

    function cleanHeap(State storage self) internal {
        while (!self.heap.isEmpty()) {
            if (depth(self, self.heap.root()) == 0) {
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
