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

    uint256 private constant _PRICE_PRECISION = 10 ** 18;
    uint256 private constant _CLAIM_BOUNTY_UNIT = 1 gwei;
    uint40 private constant _MAX_ORDER = 2 ** 15; // 32768
    uint256 private constant _MAX_ORDER_M = 2 ** 15 - 1; // % 32768

    function initialize(State storage self, IBookManager.BookKey calldata key) internal {
        if (self.isInitialized()) revert BookAlreadyInitialized();
        self.key = key;
    }

    function isInitialized(State storage self) internal view returns (bool) {
        return self.key.unitDecimals != 0;
    }

    function checkInitialized(State storage self) internal view {
        if (!self.isInitialized()) revert BookNotInitialized();
    }

    function depth(State storage self, Tick tick) internal view returns (uint64) {
        return _depth(self, tick);
    }

    function _depth(State storage self, Tick tick) private view returns (uint64) {
        return self.queues[tick].tree.total() - self.totalClaimableOf.get(tick);
    }

    function make(
        State storage self,
        mapping(OrderId => IBookManager.Order) storage orders,
        BookId bookId,
        Tick tick,
        uint64 amount
    ) internal returns (uint40 orderIndex) {
        if (!self.heap.has(tick)) {
            self.heap.push(tick);
        }

        Queue storage queue = self.queues[tick];
        orderIndex = queue.index;

        if (orderIndex >= _MAX_ORDER) {
            {
                uint40 staleOrderIndex;
                unchecked {
                    staleOrderIndex = orderIndex - _MAX_ORDER;
                }
                uint64 stalePendingAmount = orders[OrderIdLibrary.encode(bookId, tick, staleOrderIndex)].pending;
                if (stalePendingAmount > 0) {
                    // If the order is not settled completely, we cannot replace it
                    uint64 claimable = calculateClaimableRawAmount(self, stalePendingAmount, tick, staleOrderIndex);
                    if (claimable != stalePendingAmount) {
                        revert QueueReplaceFailed();
                    }
                }
            }

            // The stale order is settled completely, so remove it from the totalClaimableOf.
            // We can determine the stale order is claimable.
            uint64 staleOrderedAmount = queue.tree.get(orderIndex & _MAX_ORDER_M);
            if (staleOrderedAmount > 0) {
                self.totalClaimableOf.sub(tick, staleOrderedAmount);
            }
        }

        queue.index = orderIndex + 1;
        queue.tree.update(orderIndex & _MAX_ORDER_M, amount);
    }

    function take(State storage self, uint64 takeAmount) internal returns (Tick tick, uint256 baseAmount) {
        tick = self.heap.root();
        uint64 currentDepth = _depth(self, tick);
        if (currentDepth < takeAmount) revert TooLargeTakeAmount();

        baseAmount = tick.rawToBase(takeAmount, true);
        self.totalClaimableOf.add(tick, takeAmount);

        _cleanHeap(self);
    }

    function cancel(State storage self, Tick tick, uint40 orderIndex, IBookManager.Order storage order, uint64 to)
        internal
        returns (uint64 canceledAmount)
    {
        uint64 currentPending = order.pending;
        uint64 currentClaimable = calculateClaimableRawAmount(self, currentPending, tick, orderIndex);
        uint64 afterPending = to + currentClaimable;
        unchecked {
            if (currentPending < afterPending) {
                revert CancelFailed(currentPending - currentClaimable);
            }
            canceledAmount = currentPending - afterPending;

            order.pending = afterPending;

            self.queues[tick].tree.update(
                orderIndex & _MAX_ORDER_M, self.queues[tick].tree.get(orderIndex & _MAX_ORDER_M) - canceledAmount
            );
        }
        // todo: check clean
    }

    function _cleanHeap(State storage self) private {
        while (!self.heap.isEmpty()) {
            if (_depth(self, self.heap.root()) == 0) {
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
