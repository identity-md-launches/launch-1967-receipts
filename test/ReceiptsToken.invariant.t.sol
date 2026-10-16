// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./support/TestBase.sol";
import {Vm} from "./support/Vm.sol";
import {ReceiptsToken} from "../src/ReceiptsToken.sol";
import {IERC20Errors} from "../src/interfaces/IERC20Errors.sol";

/// @title ReceiptsHandler
/// @notice Drives the token with bounded inputs from several actors, in whatever order forge picks.
/// Every action either succeeds and records what it moved in ghost accounting, or is a failure path
/// that must revert with the exact ERC-6093 error and leave the state untouched.
/// @dev The handler never reverts on its own: inputs are bounded into the valid range for the happy
/// paths and pushed just outside it for the failure paths. A violated expectation is recorded in
/// `violation` and surfaced by `invariant_handlerSawNoViolation`; on top of that the suite runs with
/// `fail-on-revert`, so a revert the handler did not expect fails the run as well.
contract ReceiptsHandler is TestBase {
    uint256 public constant SUPPLY = 1_000_000_000 * 1e18;

    ReceiptsToken public immutable token;

    /// @dev Addresses that may send: the handler (the deployer, which starts with the supply) and
    /// four externally owned actors.
    address[] public actors;
    /// @dev The token's own address: a valid recipient that can never send, so whatever lands there
    /// is stuck. Included so the balance sum covers every place tokens can go.
    address public immutable sink;

    // Ghost accounting -----------------------------------------------------------------------------

    mapping(address => uint256) public ghost_received;
    mapping(address => uint256) public ghost_sent;
    mapping(address => mapping(address => uint256)) public ghost_allowance;

    uint256 public ghost_transfers;
    uint256 public ghost_transferFroms;
    uint256 public ghost_approvals;
    uint256 public ghost_expectedReverts;
    uint256 public ghost_privilegedCallsRejected;

    /// @dev Empty while every expectation held; the first broken one otherwise.
    string public violation;

    constructor() {
        token = new ReceiptsToken();
        sink = address(token);
        actors.push(address(this));
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA201));
        actors.push(address(0xDA4E));
        for (uint256 i = 1; i < actors.length; i++) {
            vm.label(actors[i], string(abi.encodePacked("actor", bytes1(uint8(48 + i)))));
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    /// @notice Every address that can hold a balance in this harness.
    function holders() public view returns (address[] memory list) {
        list = new address[](actors.length + 1);
        for (uint256 i = 0; i < actors.length; i++) {
            list[i] = actors[i];
        }
        list[actors.length] = sink;
    }

    // Happy paths ----------------------------------------------------------------------------------

    /// @notice A transfer of at most the sender's balance, to any actor or the sink.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 amount = bound(amountSeed, 0, token.balanceOf(from));

        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);

        vm.prank(from);
        bool ok = token.transfer(to, amount);

        _check(ok, "transfer returned false");
        if (from == to) {
            _check(token.balanceOf(from) == fromBefore, "self transfer changed the balance");
        } else {
            _check(token.balanceOf(from) == fromBefore - amount, "transfer: sender paid a different amount");
            _check(token.balanceOf(to) == toBefore + amount, "transfer: recipient received a different amount");
        }

        ghost_sent[from] += amount;
        ghost_received[to] += amount;
        ghost_transfers++;
    }

    /// @notice Sets an allowance to any value, including the infinite one.
    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        // Mostly values within the supply, sometimes the infinite sentinel, sometimes just below it.
        uint256 amount;
        uint256 pick = amountSeed % 8;
        if (pick == 0) {
            amount = type(uint256).max;
        } else if (pick == 1) {
            amount = type(uint256).max - 1;
        } else {
            amount = bound(amountSeed, 0, SUPPLY);
        }

        vm.prank(owner);
        bool ok = token.approve(spender, amount);

        _check(ok, "approve returned false");
        _check(token.allowance(owner, spender) == amount, "approve did not set the allowance");
        ghost_allowance[owner][spender] = amount;
        ghost_approvals++;
    }

    /// @notice Spends an existing allowance: at most the allowance, at most the owner's balance.
    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _recipient(toSeed);

        uint256 allowed = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 cap = allowed < balance ? allowed : balance;
        uint256 amount = bound(amountSeed, 0, cap);

        uint256 ownerBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        uint256 spenderBefore = token.balanceOf(spender);

        vm.prank(spender);
        bool ok = token.transferFrom(owner, to, amount);

        _check(ok, "transferFrom returned false");
        if (owner == to) {
            _check(token.balanceOf(owner) == ownerBefore, "transferFrom to self changed the balance");
        } else {
            _check(token.balanceOf(owner) == ownerBefore - amount, "transferFrom: owner paid a different amount");
            _check(token.balanceOf(to) == toBefore + amount, "transferFrom: recipient received a different amount");
            if (spender != owner && spender != to) {
                _check(token.balanceOf(spender) == spenderBefore, "transferFrom: the spender's balance moved");
            }
        }
        if (allowed == type(uint256).max) {
            _check(token.allowance(owner, spender) == allowed, "infinite allowance was decremented");
        } else {
            _check(token.allowance(owner, spender) == allowed - amount, "allowance did not decrease by the amount");
            ghost_allowance[owner][spender] = allowed - amount;
        }

        ghost_sent[owner] += amount;
        ghost_received[to] += amount;
        ghost_transferFroms++;
    }

    // Failure paths --------------------------------------------------------------------------------

    /// @notice One wei or more above the sender's balance must revert with the balance error.
    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) external {
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 balance = token.balanceOf(from);
        uint256 amount = balance + bound(excessSeed, 1, SUPPLY);

        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount);
        uint256 toBefore = token.balanceOf(to);

        vm.prank(from);
        try token.transfer(to, amount) returns (bool) {
            _check(false, "transfer above balance succeeded");
        } catch (bytes memory reason) {
            _check(keccak256(reason) == keccak256(expected), "transfer above balance: wrong error");
        }
        _check(token.balanceOf(from) == balance, "failed transfer changed the sender's balance");
        _check(token.balanceOf(to) == toBefore, "failed transfer changed the recipient's balance");
        ghost_expectedReverts++;
    }

    /// @notice Transfers to the zero address must revert, whatever the amount, so nothing is burned.
    function transferToZero(uint256 fromSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 amount = bound(amountSeed, 0, token.balanceOf(from));
        uint256 before = token.balanceOf(from);
        bytes memory expected = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));

        vm.prank(from);
        try token.transfer(address(0), amount) returns (bool) {
            _check(false, "transfer to the zero address succeeded");
        } catch (bytes memory reason) {
            _check(keccak256(reason) == keccak256(expected), "transfer to zero: wrong error");
        }
        _check(token.balanceOf(from) == before, "failed zero-address transfer changed the balance");
        ghost_expectedReverts++;
    }

    /// @notice Approving the zero address must revert and leave nothing behind.
    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        bytes memory expected = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));

        vm.prank(owner);
        try token.approve(address(0), amount) returns (bool) {
            _check(false, "approve of the zero spender succeeded");
        } catch (bytes memory reason) {
            _check(keccak256(reason) == keccak256(expected), "approve zero spender: wrong error");
        }
        _check(token.allowance(owner, address(0)) == 0, "the zero spender gained an allowance");
        ghost_expectedReverts++;
    }

    /// @notice Spending more than a finite allowance must revert with the allowance error, even when
    /// the owner could afford it. With an infinite allowance the balance is the only limit.
    function transferFromAboveAllowance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excessSeed)
        external
    {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _recipient(toSeed);
        uint256 allowed = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);

        uint256 amount;
        bytes memory expected;
        if (allowed == type(uint256).max) {
            amount = balance + bound(excessSeed, 1, SUPPLY);
            expected = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
        } else {
            uint256 room = type(uint256).max - allowed;
            amount = allowed + bound(excessSeed, 1, room < SUPPLY ? room : SUPPLY);
            expected =
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount);
        }

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) returns (bool) {
            _check(false, "transferFrom above the allowance succeeded");
        } catch (bytes memory reason) {
            _check(keccak256(reason) == keccak256(expected), "transferFrom above allowance: wrong error");
        }
        _check(token.allowance(owner, spender) == allowed, "failed transferFrom changed the allowance");
        _check(token.balanceOf(owner) == balance, "failed transferFrom changed the owner's balance");
        _check(token.balanceOf(to) == toBefore, "failed transferFrom changed the recipient's balance");
        ghost_expectedReverts++;
    }

    /// @notice An allowance larger than the owner's balance does not let the spender take more than
    /// the owner holds: the balance check stops it and the allowance survives intact.
    function transferFromAboveBalance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excessSeed)
        external
    {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _recipient(toSeed);
        uint256 balance = token.balanceOf(owner);
        uint256 amount = balance + bound(excessSeed, 1, SUPPLY);
        uint256 toBefore = token.balanceOf(to);

        vm.prank(owner);
        token.approve(spender, amount);
        ghost_allowance[owner][spender] = amount;
        ghost_approvals++;

        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
        vm.prank(spender);
        try token.transferFrom(owner, to, amount) returns (bool) {
            _check(false, "transferFrom above the owner's balance succeeded");
        } catch (bytes memory reason) {
            _check(keccak256(reason) == keccak256(expected), "transferFrom above balance: wrong error");
        }
        _check(token.allowance(owner, spender) == amount, "failed transferFrom spent the allowance");
        _check(token.balanceOf(owner) == balance, "failed transferFrom changed the owner's balance");
        _check(token.balanceOf(to) == toBefore, "failed transferFrom changed the recipient's balance");
        ghost_expectedReverts++;
    }

    /// @notice A common privileged entry point, tried from a random actor and from the deployer, is
    /// absent: the call reverts and no balance or the supply moves.
    function privilegedCallIsRejected(uint256 sigSeed, uint256 callerSeed, uint256 targetSeed) external {
        string[16] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "setBlacklist(address,bool)",
            "lock(address)",
            "seize(address)",
            "disableTransfers()",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)"
        ];
        address caller = _actor(callerSeed);
        address target = _actor(targetSeed);
        bytes memory data = abi.encodeWithSignature(signatures[sigSeed % signatures.length], target, SUPPLY);

        uint256 callerBefore = token.balanceOf(caller);
        uint256 targetBefore = token.balanceOf(target);

        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        _check(!ok, "a privileged call succeeded");
        _check(token.totalSupply() == SUPPLY, "a privileged call changed the supply");
        _check(token.balanceOf(caller) == callerBefore, "a privileged call changed the caller's balance");
        _check(token.balanceOf(target) == targetBefore, "a privileged call changed the target's balance");
        ghost_privilegedCallsRejected++;
    }

    // Helpers --------------------------------------------------------------------------------------

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Any actor, or (one time in six) the sink.
    function _recipient(uint256 seed) internal view returns (address) {
        uint256 i = seed % (actors.length + 1);
        return i == actors.length ? sink : actors[i];
    }

    function _check(bool condition, string memory message) internal {
        if (!condition && bytes(violation).length == 0) {
            violation = message;
        }
    }
}

/// @notice Forge's target-selector shape, declared locally since forge-std is not vendored.
struct FuzzSelector {
    address addr;
    bytes4[] selectors;
}

/// @title ReceiptsTokenInvariantTest
/// @notice Properties that must hold after every random sequence of handler calls.
/// @dev The handler never expects to revert, so a revert is itself a failure of the sequence.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract ReceiptsTokenInvariantTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    ReceiptsHandler internal handler;
    ReceiptsToken internal token;

    function setUp() public {
        handler = new ReceiptsHandler();
        token = handler.token();
    }

    // Forge reads these to decide what to call -----------------------------------------------------

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() external view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = ReceiptsHandler.transfer.selector;
        selectors[1] = ReceiptsHandler.approve.selector;
        selectors[2] = ReceiptsHandler.transferFrom.selector;
        selectors[3] = ReceiptsHandler.transferAboveBalance.selector;
        selectors[4] = ReceiptsHandler.transferToZero.selector;
        selectors[5] = ReceiptsHandler.approveZeroSpender.selector;
        selectors[6] = ReceiptsHandler.transferFromAboveAllowance.selector;
        selectors[7] = ReceiptsHandler.transferFromAboveBalance.selector;
        selectors[8] = ReceiptsHandler.privilegedCallIsRejected.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    // Invariants -----------------------------------------------------------------------------------

    /// @dev The fixed supply: no sequence of calls mints or burns.
    function invariant_totalSupplyIsConstant() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply changed");
    }

    /// @dev Conservation: every token is in a known holder, and they add up to the supply exactly.
    function invariant_balancesSumToSupply() public view {
        address[] memory holders = handler.holders();
        uint256 sum;
        for (uint256 i = 0; i < holders.length; i++) {
            sum += token.balanceOf(holders[i]);
        }
        assertEq(sum, SUPPLY, "balances do not sum to the supply");
    }

    /// @dev Flow accounting: a balance is exactly what was received minus what was sent, starting
    /// from the whole supply for the deployer and zero for everyone else.
    function invariant_balanceEqualsNetFlows() public view {
        address[] memory holders = handler.holders();
        for (uint256 i = 0; i < holders.length; i++) {
            address who = holders[i];
            uint256 initial = who == address(handler) ? SUPPLY : 0;
            uint256 expected = initial + handler.ghost_received(who) - handler.ghost_sent(who);
            assertEq(token.balanceOf(who), expected, "balance disagrees with the ghost flows");
            assertLe(token.balanceOf(who), SUPPLY, "a balance exceeds the supply");
        }
    }

    /// @dev Tokens sent to the token contract itself never come back out.
    function invariant_sinkNeverSends() public view {
        address sink = handler.sink();
        assertEq(handler.ghost_sent(sink), 0, "the sink sent tokens");
        assertEq(token.balanceOf(sink), handler.ghost_received(sink), "the sink's balance is not what it received");
    }

    /// @dev Allowances are exactly what was approved minus what was spent, and the infinite
    /// allowance stays infinite.
    function invariant_allowancesMatchGhost() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < n; j++) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.ghost_allowance(owner, spender),
                    "allowance disagrees with the ghost"
                );
            }
            assertEq(token.allowance(handler.actors(i), address(0)), 0, "the zero address holds an allowance");
        }
    }

    /// @dev Metadata is immutable.
    function invariant_metadataIsConstant() public view {
        assertEq(token.name(), "RECEIPTS", "name changed");
        assertEq(token.symbol(), "RCPTS", "symbol changed");
        assertEq(uint256(token.decimals()), 18, "decimals changed");
    }

    /// @dev Every per-call expectation the handler checked held: exact amounts moved, exact errors
    /// on the failure paths, nothing moved on a failed call.
    function invariant_handlerSawNoViolation() public view {
        assertEq(handler.violation(), "", handler.violation());
    }
}
