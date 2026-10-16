// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "./interfaces/IERC20.sol";
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
import {IERC20Errors} from "./interfaces/IERC20Errors.sol";

/// @title ERC20
/// @notice A plain ERC-20 implementation with the semantics of OpenZeppelin Contracts v5 `ERC20`:
/// custom errors from ERC-6093, zero-value transfers allowed, an allowance of `type(uint256).max`
/// treated as infinite, and no hooks, fees, pausing or admin.
/// @dev Written into this repository rather than vendored so the project has no external
/// dependency to fetch. It is deliberately minimal: `_mint` is the only way the supply grows, it is
/// internal, and `ReceiptsToken` calls it exactly once from its constructor.
abstract contract ERC20 is IERC20, IERC20Metadata, IERC20Errors {
    mapping(address account => uint256) private _balances;
    mapping(address account => mapping(address spender => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /// @notice See {IERC20Metadata}.
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /// @notice See {IERC20Metadata}.
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /// @notice See {IERC20Metadata}.
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /// @notice See {IERC20}.
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /// @notice See {IERC20}.
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    /// @notice See {IERC20}.
    function transfer(address to, uint256 value) public virtual returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice See {IERC20}.
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @notice See {IERC20}.
    function approve(address spender, uint256 value) public virtual returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /// @notice See {IERC20}.
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    /// @dev Moves `value` from `from` to `to`; neither may be the zero address.
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    /// @dev The single balance-changing primitive. `from == address(0)` mints, `to == address(0)`
    /// burns; nothing in this project calls it with `to == address(0)`.
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // fromBalance >= value was checked above.
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // value was either minted above or subtracted from a balance that is part of the supply.
                _totalSupply -= value;
            }
        } else {
            unchecked {
                // The sum of all balances never exceeds _totalSupply, whose increase is checked.
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /// @dev Creates `value` tokens for `account`. Internal: only a constructor in this project calls it.
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /// @dev Sets `spender`'s allowance over `owner`'s tokens to `value` and emits `Approval`.
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /// @dev Variant used when spending an allowance, where the `Approval` event is skipped as in
    /// OpenZeppelin v5.
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /// @dev Reduces `spender`'s allowance by `value`, leaving an infinite allowance untouched.
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}
