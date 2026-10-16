// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IERC20Errors
/// @notice The ERC-20 custom errors of ERC-6093, so integrators and tests can match failures exactly.
interface IERC20Errors {
    /// @dev `sender` holds `balance` but the transfer needs `needed`.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @dev The token sender is not allowed (the zero address).
    error ERC20InvalidSender(address sender);

    /// @dev The token receiver is not allowed (the zero address).
    error ERC20InvalidReceiver(address receiver);

    /// @dev `spender` may spend `allowance` but the transfer needs `needed`.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @dev The approver is not allowed (the zero address).
    error ERC20InvalidApprover(address approver);

    /// @dev The spender is not allowed (the zero address).
    error ERC20InvalidSpender(address spender);
}
