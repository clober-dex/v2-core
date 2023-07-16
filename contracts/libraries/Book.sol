// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@clober/library/contracts/SegmentedSegmentTree.sol";
import "./Tick.sol";
import "./OrderId.sol";

library Book {
    using SegmentedSegmentTree for SegmentedSegmentTree.Core;

    uint256 private constant _MAX_ORDER = 2**15; // 32768
    uint256 private constant _MAX_ORDER_M = 2**15 - 1; // % 32768

    struct Queue {
        SegmentedSegmentTree.Core tree;
        uint256 index; // index of where the next order would go
    }

    struct Order {
        uint64 initial;
        uint64 claimed;
        uint64 open;
        uint64 bounty;
        address owner;
        address provider;
    }

    struct State {
        mapping(Tick tick => Queue) queues;
        // TODO: add heap
        // four values of totalClaimable are stored in one uint256
        mapping(uint24 groupIndex => uint256) totalClaimableOf;
        mapping(uint256 index => Order) orders;
    }

    function make(
        State storage self,
        uint128 n,
        address user,
        Tick tick,
        uint64 amount,
        address provider,
        uint64 bounty
    ) internal returns (OrderId id) {
        // TODO: add tick to heap

        Queue storage queue = self.queues[tick];
        uint256 index = queue.index;

        if (index >= _MAX_ORDER) {
            if (self.orders[index - _MAX_ORDER].open > 0) {
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
            claimed: 0,
            open: amount,
            bounty: bounty,
            owner: user,
            provider: provider
        });
        return OrderIdLibrary.encode(n, tick, index);
    }

    function take(State storage self, uint64 amount) internal {
        // TODO: update totalClaimableOf, add amount
    }

    function spend(State storage self, uint64 amount) internal {
        // TODO: update totalClaimableOf, add amount
    }
}
