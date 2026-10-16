// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./support/TestBase.sol";
import {ReceiptsToken} from "../src/ReceiptsToken.sol";
import {IERC20Errors} from "../src/interfaces/IERC20Errors.sol";

/// @title ReceiptsTokenPropertiesTest
/// @notice Stateless properties at the arithmetic edges, with inputs bounded (never discarded) so
/// every run checks something, and the edges the fuzzer might miss pinned as plain unit tests.
/// forge-config: default.fuzz.runs = 1000
contract ReceiptsTokenPropertiesTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    uint256 internal constant MAX = type(uint256).max;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    ReceiptsToken internal token;
    address internal deployer;

    function setUp() public {
        token = new ReceiptsToken();
        deployer = address(this);
    }

    // ---------------------------------------------------------------------------------------------
    // Pinned edges: zero, one wei, the full supply, the maximum
    // ---------------------------------------------------------------------------------------------

    function test_transfer_oneWei() public {
        assertTrue(token.transfer(ALICE, 1), "transfer returned false");
        assertEq(token.balanceOf(ALICE), 1, "alice");
        assertEq(token.balanceOf(deployer), SUPPLY - 1, "deployer");
    }

    function test_transfer_supplyPlusOneReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
    }

    function test_transfer_maxUintReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, MAX));
        token.transfer(ALICE, MAX);
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer balance moved");
    }

    function test_transfer_zeroToZeroAddressStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transfer_toTheTokenItselfIsAllowedAndStuck() public {
        // Nothing in the token can move its own balance: the README documents this as unrecoverable.
        assertTrue(token.transfer(address(token), 5), "transfer returned false");
        assertEq(token.balanceOf(address(token)), 5, "the token holds what it was sent");
        (bool ok,) = address(token).call(abi.encodeWithSignature("recover(address)", deployer));
        assertFalse(ok, "a recovery entry point exists");
        assertEq(token.balanceOf(address(token)), 5, "the stuck balance moved");
    }

    function test_approve_zeroClearsAllowance() public {
        token.approve(BOB, 100);
        token.approve(BOB, 0);
        assertEq(token.allowance(deployer, BOB), 0, "allowance not cleared");
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, uint256(0), uint256(1))
        );
        token.transferFrom(deployer, ALICE, 1);
    }

    function test_approve_maxMinusOneIsFiniteAndDecremented() public {
        token.approve(BOB, MAX - 1);
        vm.prank(BOB);
        token.transferFrom(deployer, ALICE, 1);
        assertEq(token.allowance(deployer, BOB), MAX - 2, "max-1 was treated as infinite");
    }

    function test_approve_fromZeroAddressReverts() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(BOB, 1);
    }

    function test_transfer_fromZeroAddressReverts() public {
        // The sender check comes before the balance check, so the error names the invalid sender.
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(ALICE, 1);
    }

    function test_transfer_zeroAmountFromZeroAddressReverts() public {
        // Even a zero-value transfer may not originate from the zero address.
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(ALICE, 0);
    }

    function test_transferFrom_zeroAddressOwnerReverts() public {
        // Nobody can hold an allowance from the zero address, so any positive amount fails on it.
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, uint256(0), uint256(1))
        );
        token.transferFrom(address(0), ALICE, 1);

        // A zero amount passes the allowance comparison, but writing the (unchanged) allowance back
        // for a zero-address owner is itself rejected, as in OpenZeppelin v5.
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_transferFrom_ownerAsSpenderStillNeedsAllowance() public {
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, uint256(0), uint256(1))
        );
        token.transferFrom(ALICE, BOB, 1);

        vm.prank(ALICE);
        token.approve(ALICE, 1);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(ALICE, BOB, 1), "self-approved transferFrom returned false");
        assertEq(token.balanceOf(BOB), 1, "bob");
        assertEq(token.allowance(ALICE, ALICE), 0, "self allowance not spent");
    }

    function test_transferFrom_exactAllowanceThenOneMoreReverts() public {
        token.approve(BOB, 50);
        vm.prank(BOB);
        token.transferFrom(deployer, ALICE, 50);
        assertEq(token.allowance(deployer, BOB), 0, "allowance not exhausted");
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, uint256(0), uint256(1))
        );
        token.transferFrom(deployer, ALICE, 1);
    }

    function test_transferFrom_zeroAmountWithoutAllowanceSucceeds() public {
        // OpenZeppelin v5 semantics: a zero spend needs no allowance and emits a zero Transfer.
        vm.prank(BOB);
        assertTrue(token.transferFrom(deployer, ALICE, 0), "zero transferFrom returned false");
        assertEq(token.balanceOf(ALICE), 0, "alice gained tokens");
    }

    function test_transferFrom_infiniteAllowanceCannotExceedBalance() public {
        token.transfer(ALICE, 7);
        vm.prank(ALICE);
        token.approve(BOB, MAX);
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, uint256(7), uint256(8))
        );
        token.transferFrom(ALICE, CAROL, 8);
        assertEq(token.allowance(ALICE, BOB), MAX, "infinite allowance changed on a failed call");
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok, "an unknown selector did not revert");
        (ok,) = address(token).call("");
        assertFalse(ok, "an empty call did not revert");
    }

    function test_decimalsIsNotAStorageValue() public {
        // Decimals come from a constant, not a storage slot: a fresh deployment answers 18 as well.
        ReceiptsToken other = new ReceiptsToken();
        assertEq(uint256(other.decimals()), 18, "decimals");
        assertEq(other.totalSupply(), SUPPLY, "second deployment supply");
        assertEq(token.totalSupply(), SUPPLY, "first deployment supply changed");
    }

    // ---------------------------------------------------------------------------------------------
    // Bounded fuzz properties
    // ---------------------------------------------------------------------------------------------

    /// @dev Round trip: sending and sending back lands everyone where they started.
    function testFuzz_transferRoundTripIsNetZero(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        token.transfer(ALICE, amount);
        vm.prank(ALICE);
        token.transfer(deployer, amount);
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer did not get everything back");
        assertEq(token.balanceOf(ALICE), 0, "alice kept something");
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
    }

    /// @dev Splitting one transfer into pieces delivers the same total: no per-transfer fee or rounding.
    function testFuzz_splitTransfersDeliverTheSameTotal(uint256 totalSeed, uint256 partsSeed) public {
        uint256 total = bound(totalSeed, 0, SUPPLY);
        uint256 parts = bound(partsSeed, 1, 16);
        uint256 each = total / parts;
        uint256 sent;
        for (uint256 i = 0; i < parts; i++) {
            uint256 piece = i == parts - 1 ? total - sent : each;
            token.transfer(BOB, piece);
            sent += piece;
        }
        assertEq(sent, total, "harness: pieces do not add up");
        assertEq(token.balanceOf(BOB), total, "bob received a different total");
        assertEq(token.balanceOf(deployer), SUPPLY - total, "deployer paid a different total");
    }

    /// @dev A chain of hops delivers the full amount to the last hop, whatever the route.
    function testFuzz_multiHopArrivesWhole(uint256 amountSeed, uint8 hops) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 n = bound(hops, 1, 8);
        address prev = deployer;
        for (uint256 i = 1; i <= n; i++) {
            address next = address(uint160(0x1000 + i));
            vm.prank(prev);
            assertTrue(token.transfer(next, amount), "hop returned false");
            if (i > 1) {
                assertEq(token.balanceOf(prev), 0, "an intermediate hop kept tokens");
            }
            prev = next;
        }
        assertEq(token.balanceOf(prev), amount, "the last hop received a different amount");
        assertEq(token.balanceOf(deployer), SUPPLY - amount, "deployer");
    }

    /// @dev Approving twice is the same as approving once with the last value (overwrite, not add).
    function testFuzz_approveOverwritesNotAccumulates(uint256 first, uint256 second) public {
        token.approve(BOB, first);
        token.approve(BOB, second);
        assertEq(token.allowance(deployer, BOB), second, "allowance is not the last value");
        token.approve(BOB, second);
        assertEq(token.allowance(deployer, BOB), second, "a repeated approve changed the allowance");
    }

    /// @dev An allowance granted by one owner does not let the spender move anyone else's tokens.
    function testFuzz_allowanceIsPerOwner(uint256 allowedSeed, uint256 heldSeed) public {
        uint256 allowed = bound(allowedSeed, 1, SUPPLY);
        uint256 held = bound(heldSeed, 1, SUPPLY);
        token.transfer(ALICE, held);
        token.approve(BOB, allowed); // the deployer approves bob, alice does not
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, uint256(0), uint256(1))
        );
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), held, "alice's balance moved");
        assertEq(token.allowance(deployer, BOB), allowed, "the deployer's allowance was touched");
    }

    /// @dev Spending an allowance in several transferFrom calls decrements it exactly, and the call
    /// that would take it below zero reverts with the remaining allowance in the error.
    function testFuzz_allowanceDecrementsExactlyAcrossCalls(uint256 allowedSeed, uint256 stepSeed) public {
        uint256 allowed = bound(allowedSeed, 1, SUPPLY);
        uint256 step = bound(stepSeed, 1, allowed);
        token.approve(BOB, allowed);
        uint256 spent;
        while (spent + step <= allowed) {
            vm.prank(BOB);
            token.transferFrom(deployer, ALICE, step);
            spent += step;
            assertEq(token.allowance(deployer, BOB), allowed - spent, "allowance off after a step");
            if (spent > 32 * step) break; // keep the loop short; the property is per step
        }
        uint256 remaining = allowed - spent;
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, remaining, remaining + 1)
        );
        token.transferFrom(deployer, ALICE, remaining + 1);
        assertEq(token.balanceOf(ALICE), spent, "alice holds a different amount than was spent");
    }

    /// @dev Only the infinite sentinel is infinite: any other allowance decrements.
    function testFuzz_onlyMaxAllowanceIsInfinite(uint256 allowedSeed) public {
        uint256 allowed = bound(allowedSeed, 1, MAX);
        token.approve(BOB, allowed);
        vm.prank(BOB);
        token.transferFrom(deployer, ALICE, 1);
        if (allowed == MAX) {
            assertEq(token.allowance(deployer, BOB), MAX, "infinite allowance decremented");
        } else {
            assertEq(token.allowance(deployer, BOB), allowed - 1, "finite allowance not decremented");
        }
    }

    /// @dev Any recipient other than the zero address can receive, including contracts and precompiles.
    function testFuzz_anyNonZeroRecipientReceivesExactly(address toSeed, uint256 amountSeed) public {
        address to = toSeed == address(0) ? address(1) : toSeed;
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 toBefore = token.balanceOf(to);
        uint256 deployerBefore = token.balanceOf(deployer);
        assertTrue(token.transfer(to, amount), "transfer returned false");
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), deployerBefore, "self transfer changed the balance");
        } else {
            assertEq(token.balanceOf(to), toBefore + amount, "recipient received a different amount");
            assertEq(token.balanceOf(deployer), deployerBefore - amount, "deployer paid a different amount");
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
    }

    /// @dev A failed transfer is atomic: whoever the sender and whatever the excess, nothing moves.
    function testFuzz_failedTransferMovesNothing(uint256 heldSeed, uint256 excessSeed) public {
        uint256 held = bound(heldSeed, 0, SUPPLY);
        uint256 excess = bound(excessSeed, 1, MAX - SUPPLY);
        token.transfer(ALICE, held);
        uint256 attempt = held + excess;
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, attempt));
        token.transfer(BOB, attempt);
        assertEq(token.balanceOf(ALICE), held, "alice");
        assertEq(token.balanceOf(BOB), 0, "bob");
        assertEq(token.balanceOf(deployer), SUPPLY - held, "deployer");
    }

    /// @dev The sender's balance is the only thing that bounds a transfer: with the whole supply
    /// in one account, exactly SUPPLY is the largest amount that succeeds.
    function testFuzz_wholeSupplyIsTheCeiling(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 0, MAX);
        if (amount <= SUPPLY) {
            assertTrue(token.transfer(ALICE, amount), "transfer within the supply failed");
            assertEq(token.balanceOf(ALICE), amount, "alice");
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
            );
            token.transfer(ALICE, amount);
            assertEq(token.balanceOf(ALICE), 0, "alice received from a failed transfer");
        }
    }
}
