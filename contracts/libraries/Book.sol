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

    event Take(BookId indexed bookId, address indexed user, Tick tick, uint64 amount);
    event Make(
        BookId indexed bookId, address indexed user, uint64 amount, uint32 claimBounty, uint256 orderIndex, Tick tick
    );
    event Cancel(OrderId indexed orderId, uint64 canceledAmount);
    event Claim(address indexed claimer, OrderId indexed orderId, uint64 rawAmount, uint32 claimBounty);

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

    function initialize(State storage self, IBookManager.BookKey calldata key) external {
        if (self.key.unitDecimals != 0) revert BookAlreadyInitialized();
        self.key = key;
    }

    function depth(State storage self, Tick tick) external view returns (uint64) {
        return _depth(self, tick);
    }

    function _depth(State storage self, Tick tick) private view returns (uint64) {
        return self.queues[tick].tree.total() - self.totalClaimableOf.get(tick);
    }

    function make(
        State storage self,
        mapping(OrderId => IBookManager.Order) storage orders,
        BookId bookId,
        address user,
        Tick tick,
        uint64 amount,
        address provider,
        uint32 bounty
    ) external returns (OrderId id) {
        if (!self.heap.has(tick)) {
            self.heap.push(tick);
        }

        Queue storage queue = self.queues[tick];
        uint40 index = queue.index;

        if (index >= _MAX_ORDER) {
            {
                uint40 staleOrderIndex;
                unchecked {
                    staleOrderIndex = index - _MAX_ORDER;
                }
                uint64 stalePendingAmount = orders[OrderIdLibrary.encode(bookId, tick, staleOrderIndex)].pending;
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
        orders[id] = IBookManager.Order({
            initial: amount,
            nonce: 0,
            owner: user,
            pending: amount,
            bounty: bounty,
            provider: provider
        });
        emit Make(bookId, user, amount, bounty, index, tick);
    }

    function take(State storage self, uint64 takeAmount) external returns (uint256 baseAmount) {
        Tick tick = self.heap.root();
        uint64 currentDepth = _depth(self, tick);
        if (currentDepth < takeAmount) revert TooLargeTakeAmount();

        baseAmount = tick.rawToBase(takeAmount, true);
        self.totalClaimableOf.add(tick, takeAmount);

        _cleanHeap(self);
    }

    function cancel(State storage self, OrderId id, IBookManager.Order storage order, uint64 to)
        external
        returns (uint64 canceledAmount)
    {
        (, Tick tick, uint40 orderIndex) = id.decode();
        uint64 claimableRawAmount = _calculateClaimableRawAmount(self, to, tick, orderIndex);
        uint64 afterPendingAmount = to + claimableRawAmount;
        uint64 pending = order.pending;
        unchecked {
            if (pending < afterPendingAmount) {
                revert CancelFailed(pending - claimableRawAmount);
            }
            canceledAmount = pending - afterPendingAmount;
        }
        order.pending = afterPendingAmount;

        self.queues[tick].tree.update(
            orderIndex & _MAX_ORDER_M, self.queues[tick].tree.get(orderIndex & _MAX_ORDER_M) - canceledAmount
        );
        emit Cancel(id, canceledAmount);
    }

    function claim(State storage self, OrderId id, IBookManager.Order storage order)
        external
        returns (uint64 claimedRaw, uint256 claimedAmount)
    {
        (, Tick tick, uint40 orderIndex) = id.decode();
        uint64 pending = order.pending;
        claimedRaw = _calculateClaimableRawAmount(self, pending, tick, orderIndex);
        order.pending = pending - claimedRaw;
        claimedAmount = tick.rawToBase(claimedRaw, false);
        emit Claim(msg.sender, id, claimedRaw, order.bounty);
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
