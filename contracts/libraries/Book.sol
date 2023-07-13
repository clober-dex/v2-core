// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@clober/library/contracts/SegmentedSegmentTree.sol";

type Tick is uint24; // TODO: create tick library

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
        uint64 reduced;
        uint64 open;
        uint64 bounty;
        bool locked;
        address owner;
        address provider;
    }

    struct State {
        mapping(Tick => Queue) queues;
        // TODO: add heap
        // four values of totalClaimable are stored in one uint256
        mapping(uint24 groupIndex => uint256) totalClaimableOf;
        mapping(uint256 => Order) orders;
    }

    function make(
        State storage self,
        address owner,
        Tick tick,
        uint64 amount,
        uint64 bounty,
        address provider
    ) internal returns (uint256 index) {
        // TODO: add tick to heap

        Queue storage queue = self.queues[tick];
        index = queue.index;

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
            reduced: 0,
            open: amount,
            bounty: bounty,
            locked: false,
            owner: owner,
            provider: provider
        });
    }

    function take(State storage self, uint64 amount) internal {
        // TODO: update totalClaimableOf, add amount
    }
}
