pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/libraries/OrderId.sol";

contract OrderIdTest is Test {
    using OrderIdLibrary for OrderId;

    function testEncode() public {
        OrderId id = OrderIdLibrary.encode(1, 2, 3);
        assertEq(OrderId.unwrap(id), 0x100000200000000000000000000000003);
    }

    function testDecode() public {
        OrderId id = OrderId.wrap(0x100000200000000000000000000000003);
        uint128 n;
        uint24 tick;
        uint256 index;
        (n, tick, index) = id.decode();
        assertEq(n, uint128(1));
        assertEq(tick, uint24(2));
        assertEq(index, uint256(3));
    }
}
