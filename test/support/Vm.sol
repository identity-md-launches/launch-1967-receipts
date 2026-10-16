// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Vm
/// @notice The subset of Foundry cheatcodes these tests use, declared with their canonical
/// signatures so the selectors match the ones forge serves at the cheatcode address.
/// @dev Declared here instead of vendoring forge-std: the project then has no dependency to fetch
/// and the offline verifier cannot miss one.
interface Vm {
    /// @notice Sets `msg.sender` for the next call or contract creation.
    function prank(address msgSender) external;

    /// @notice Sets `msg.sender` for every subsequent call until `stopPrank`.
    function startPrank(address msgSender) external;

    /// @notice Ends a `startPrank`.
    function stopPrank() external;

    /// @notice Expects the next call to revert with exactly `revertData`.
    function expectRevert(bytes calldata revertData) external;

    /// @notice Expects the next call to revert with the custom error or selector `revertData`.
    function expectRevert(bytes4 revertData) external;

    /// @notice Expects the next call to emit the event emitted right after this cheatcode.
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;

    /// @notice Discards the current fuzz input when `condition` is false.
    function assume(bool condition) external pure;

    /// @notice Labels an address in traces.
    function label(address account, string calldata newLabel) external;
}
