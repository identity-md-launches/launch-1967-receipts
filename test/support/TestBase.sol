// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "./Vm.sol";

/// @title TestBase
/// @notice A minimal test base: the cheatcode handle and assertions that revert with a message, so a
/// failed assertion fails the test under every forge version without depending on forge-std.
abstract contract TestBase {
    /// @dev The address forge serves cheatcodes at: `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    Vm internal constant vm = Vm(VM_ADDRESS);

    function assertTrue(bool condition, string memory err) internal pure {
        require(condition, err);
    }

    function assertFalse(bool condition, string memory err) internal pure {
        require(!condition, err);
    }

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        require(a == b, err);
    }

    function assertEq(address a, address b, string memory err) internal pure {
        require(a == b, err);
    }

    function assertEq(string memory a, string memory b, string memory err) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), err);
    }

    function assertGt(uint256 a, uint256 b, string memory err) internal pure {
        require(a > b, err);
    }

    function assertLe(uint256 a, uint256 b, string memory err) internal pure {
        require(a <= b, err);
    }

    /// @dev Maps any `x` into `[min, max]` without discarding the run, so every fuzz case is a real
    /// case. Small inputs land on the edges first (min, max, min+1, max-1), then wrap into the range.
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256 result) {
        require(min <= max, "bound: min > max");
        if (x >= min && x <= max) return x;
        uint256 size = max - min + 1;
        if (size == 0) {
            // The full uint256 range: nothing to do.
            return x;
        }
        if (x <= 3 && size > x) {
            // 0,1,2,3 -> min, min+1, min+2, min+3
            return min + x;
        }
        if (x >= type(uint256).max - 3 && size > type(uint256).max - x) {
            // max-3..max -> max-3..max
            return max - (type(uint256).max - x);
        }
        if (x > max) {
            uint256 diff = x - max;
            uint256 rem = diff % size;
            if (rem == 0) return max;
            result = min + rem - 1;
        } else {
            uint256 diff = min - x;
            uint256 rem = diff % size;
            if (rem == 0) return min;
            result = max - rem + 1;
        }
    }
}
