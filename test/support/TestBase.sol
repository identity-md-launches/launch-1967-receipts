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
}
