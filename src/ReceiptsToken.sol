// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "./ERC20.sol";

/// @title ReceiptsToken
/// @notice RECEIPTS (RCPTS): a fixed-supply ERC-20. One billion tokens with 18 decimals are minted
/// once, in the constructor, to the deployer (`msg.sender`). On the IdentityMD launch the deployer is
/// the ProjectFactory, which distributes the whole supply.
/// @dev No owner, no mint, no burn, no pause, no fee, no blocklist: the supply can never grow and no
/// privileged address can move or freeze a holder's balance. Transfers always move exactly the
/// amount requested, so the launch flows (factory to distributor, pool seed, swaps through the
/// PoolManager) arrive whole without any exemption list.
contract ReceiptsToken is ERC20 {
    /// @notice The ERC-20 `name()`.
    string public constant TOKEN_NAME = "RECEIPTS";

    /// @notice The ERC-20 `symbol()`.
    string public constant TOKEN_SYMBOL = "RCPTS";

    /// @notice The whole supply in minor units: 1,000,000,000 tokens at 18 decimals.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 1e18;

    /// @notice Mints the whole supply to the deployer. Takes no arguments and calls no other contract.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
