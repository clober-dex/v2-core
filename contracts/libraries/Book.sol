// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@clober/library/contracts/SegmentedSegmentTree.sol";

import "../interfaces/IBookManager.sol";
import "./Tick.sol";
import "./OrderId.sol";
import "./TotalClaimableMap.sol";
import "./TickBitmap.sol";

library Book {
    using Book for State;
    using TickBitmap for mapping(uint256 => uint256);
    using SegmentedSegmentTree for SegmentedSegmentTree.Core;
    using TotalClaimableMap for mapping(uint24 => uint256);
    using TickLibrary for *;
    using OrderIdLibrary for OrderId;

    error ZeroAmount();
    error BookAlreadyOpened();
    error BookNotOpened();
    error OrdersOutOfRange();
    error QueueReplaceFailed();
    error TooLargeTakeAmount();
    error CancelFailed(uint64 maxCancelableAmount);

    // @dev Due to the segment tree implementation, the maximum order size is 2 ** 15.
    uint40 internal constant MAX_ORDER = 2 ** 15; // 32768
    uint256 internal constant MAX_ORDER_M = 2 ** 15 - 1; // % 32768

    struct Order {
        address provider;
        uint64 pending; // @dev unfilled amount + filled(claimable) amount
    }

    struct Queue {
        SegmentedSegmentTree.Core tree;
        Order[] orders;
    }

    struct State {
        IBookManager.BookKey key;
        mapping(Tick tick => Queue) queues;
        mapping(uint256 => uint256) tickBitmap;
        // @dev Four values of totalClaimable are stored in one uint256
        mapping(uint24 groupIndex => uint256) totalClaimableOf;
    }

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

    function lowest(State storage self) internal view returns (Tick) {
        return self.tickBitmap.lowest().toTick();
    }

    function isEmpty(State storage self) internal view returns (bool) {
        return self.tickBitmap.isEmpty();
    }

    function _getOrder(State storage self, Tick tick, uint40 index) private view returns (Order storage) {
        return self.queues[tick].orders[index];
    }

    function getOrder(State storage self, Tick tick, uint40 index) internal view returns (Order memory) {
        return _getOrder(self, tick, index);
    }

    function make(State storage self, Tick tick, uint64 amount, address provider)
        internal
        returns (uint40 orderIndex)
    {
        if (amount == 0) revert ZeroAmount();
        uint24 tickIndex = tick.toUint24();
        if (!self.tickBitmap.has(tickIndex)) self.tickBitmap.set(tickIndex);

        Queue storage queue = self.queues[tick];
        // @dev Assume that orders.length cannot reach to type(uint40).max + 1.
        orderIndex = SafeCast.toUint40(queue.orders.length);

        if (orderIndex >= MAX_ORDER) {
            unchecked {
                uint40 staleOrderIndex = orderIndex - MAX_ORDER;
                uint64 stalePendingAmount = queue.orders[staleOrderIndex].pending;
                if (stalePendingAmount > 0) {
                    // If the order is not settled completely, we cannot replace it
                    uint64 claimable = self.calculateClaimableRawAmount(tick, staleOrderIndex);
                    if (claimable != stalePendingAmount) revert QueueReplaceFailed();
                }
            }

            // The stale order is settled completely, so remove it from the totalClaimableOf.
            // We can determine the stale order is claimable.
            uint64 staleOrderedAmount = queue.tree.get(orderIndex & MAX_ORDER_M);
            if (staleOrderedAmount > 0) self.totalClaimableOf.sub(tick, staleOrderedAmount);
        }

        queue.tree.update(orderIndex & MAX_ORDER_M, amount);

        queue.orders.push(Order({pending: amount, provider: provider}));
    }

    /**
     * @notice Take orders from the book
     * @param self The book state
     * @param maxTakeAmount The maximum amount to take
     * @return takenAmount The actual amount to take
     */
    function take(State storage self, Tick tick, uint64 maxTakeAmount) internal returns (uint64 takenAmount) {
        uint64 currentDepth = depth(self, tick);
        if (currentDepth > maxTakeAmount) {
            takenAmount = maxTakeAmount;
        } else {
            takenAmount = currentDepth;
            self.tickBitmap.clear(tick.toUint24());
        }

        self.totalClaimableOf.add(tick, takenAmount);
    }

    function cancel(State storage self, OrderId orderId, uint64 to)
        internal
        returns (uint64 canceled, uint64 afterPending)
    {
        (, Tick tick, uint40 orderIndex) = orderId.decode();
        Queue storage queue = self.queues[tick];
        uint64 pending = queue.orders[orderIndex].pending;
        uint64 claimableRaw = self.calculateClaimableRawAmount(tick, orderIndex);
        afterPending = to + claimableRaw;
        unchecked {
            if (pending < afterPending) revert CancelFailed(pending - claimableRaw);
            canceled = pending - afterPending;

            self.queues[tick].tree.update(
                orderIndex & MAX_ORDER_M, self.queues[tick].tree.get(orderIndex & MAX_ORDER_M) - canceled
            );
        }
        queue.orders[orderIndex].pending = afterPending;

        if (depth(self, tick) == 0) {
            // clear() won't revert so we can cancel with to=0 even if the depth() is already zero
            // works even if bitmap is empty
            self.tickBitmap.clear(tick.toUint24());
        }
    }

    function claim(State storage self, Tick tick, uint40 index) internal returns (uint64 claimedRaw) {
        Order storage order = _getOrder(self, tick, index);

        claimedRaw = self.calculateClaimableRawAmount(tick, index);
        unchecked {
            order.pending -= claimedRaw;
        }
    }

    function calculateClaimableRawAmount(State storage self, Tick tick, uint40 index) internal view returns (uint64) {
        uint64 orderAmount = self.getOrder(tick, index).pending;

        Queue storage queue = self.queues[tick];
        // @dev Book logic always considers replaced orders as claimable.
        unchecked {
            if (uint256(index) + MAX_ORDER < queue.orders.length) return orderAmount;
            uint64 totalClaimable = self.totalClaimableOf.get(tick);
            uint64 rangeRight = _getClaimRangeRight(queue, index);
            if (rangeRight - orderAmount >= totalClaimable) return 0;

            // -------- totalClaimable ---------|---
            // ------|---- orderAmount ----|--------
            //   rangeLeft           rangeRight
            if (rangeRight <= totalClaimable) return orderAmount;
            // -- totalClaimable --|----------------
            // ------|---- orderAmount ----|--------
            //   rangeLeft           rangeRight
            else return totalClaimable - (rangeRight - orderAmount);
        }
    }

    function _getClaimRangeRight(Queue storage queue, uint256 orderIndex) private view returns (uint64 rangeRight) {
        uint256 l = queue.orders.length & MAX_ORDER_M;
        uint256 r = (orderIndex + 1) & MAX_ORDER_M;
        rangeRight = (l < r) ? queue.tree.query(l, r) : queue.tree.total() - queue.tree.query(r, l);
    }
}
