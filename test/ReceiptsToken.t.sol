// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./support/TestBase.sol";
import {ReceiptsToken} from "../src/ReceiptsToken.sol";
import {IERC20Errors} from "../src/interfaces/IERC20Errors.sol";

/// @notice Deploys the token from a contract that is not the test, to show the supply goes to
/// whichever address runs the constructor (on the launch, the ProjectFactory).
contract DeployerProbe {
    ReceiptsToken public immutable token;

    constructor() {
        token = new ReceiptsToken();
    }
}

contract ReceiptsTokenTest is TestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    uint256 internal constant EIP170_LIMIT = 24_576;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    ReceiptsToken internal token;
    /// @dev The test contract deploys the token, so it is the deployer and holds the supply.
    address internal deployer;

    function setUp() public {
        token = new ReceiptsToken();
        deployer = address(this);
        vm.label(ALICE, "alice");
        vm.label(BOB, "bob");
        vm.label(CAROL, "carol");
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and supply
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "RECEIPTS", "name");
        assertEq(token.symbol(), "RCPTS", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    function test_constantsMatchTheBrief() public view {
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "INITIAL_SUPPLY is not one billion tokens at 18 decimals");
        assertEq(token.INITIAL_SUPPLY(), 1_000_000_000_000_000_000_000_000_000, "INITIAL_SUPPLY in minor units");
        assertEq(token.TOKEN_NAME(), "RECEIPTS", "TOKEN_NAME");
        assertEq(token.TOKEN_SYMBOL(), "RCPTS", "TOKEN_SYMBOL");
    }

    function test_wholeSupplyMintedOnceToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply");
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer balance");
        assertEq(token.balanceOf(address(token)), 0, "the token holds nothing itself");
    }

    function test_supplyGoesToWhoeverDeploys() public {
        DeployerProbe probe = new DeployerProbe();
        ReceiptsToken deployed = probe.token();
        assertEq(deployed.totalSupply(), SUPPLY, "probe deployment supply");
        assertEq(deployed.balanceOf(address(probe)), SUPPLY, "the deploying contract holds the supply");
        assertEq(deployed.balanceOf(address(this)), 0, "the test did not receive the probe's supply");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer
    // ---------------------------------------------------------------------------------------------

    function test_transfer_movesExactAmountAndEmits() public {
        uint256 amount = 1_234 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Transfer(deployer, ALICE, amount);
        assertTrue(token.transfer(ALICE, amount), "transfer returned false");
        assertEq(token.balanceOf(ALICE), amount, "recipient balance");
        assertEq(token.balanceOf(deployer), SUPPLY - amount, "sender balance");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transfer_wholeBalance() public {
        assertTrue(token.transfer(ALICE, SUPPLY), "transfer returned false");
        assertEq(token.balanceOf(ALICE), SUPPLY, "alice holds everything");
        assertEq(token.balanceOf(deployer), 0, "deployer holds nothing");
    }

    function test_transfer_zeroAmountIsAllowed() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0), "zero transfer returned false");
        assertEq(token.balanceOf(ALICE), 0, "alice");
        assertEq(token.balanceOf(BOB), 0, "bob");
    }

    function test_transfer_toSelfKeepsBalance() public {
        token.transfer(ALICE, 500);
        vm.prank(ALICE);
        token.transfer(ALICE, 500);
        assertEq(token.balanceOf(ALICE), 500, "self transfer changed the balance");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transfer_secondHopArrivesWhole() public {
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.transfer(BOB, 1_000);
        assertEq(token.balanceOf(BOB), 1_000, "bob received the full amount");
        assertEq(token.balanceOf(ALICE), 0, "alice kept nothing back");
    }

    function test_transfer_revertsWhenBalanceInsufficient() public {
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, uint256(0), uint256(1))
        );
        token.transfer(BOB, 1);
    }

    function test_transfer_revertsOneAboveBalance() public {
        token.transfer(ALICE, 100);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, uint256(100), uint256(101))
        );
        token.transfer(BOB, 101);
        assertEq(token.balanceOf(ALICE), 100, "a failed transfer changed the balance");
    }

    function test_transfer_revertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.totalSupply(), SUPPLY, "nothing was burned");
    }

    // ---------------------------------------------------------------------------------------------
    // approve / transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_approve_setsAllowanceAndEmits() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(deployer, BOB, 777);
        assertTrue(token.approve(BOB, 777), "approve returned false");
        assertEq(token.allowance(deployer, BOB), 777, "allowance");
    }

    function test_approve_overwritesPreviousAllowance() public {
        token.approve(BOB, 777);
        token.approve(BOB, 5);
        assertEq(token.allowance(deployer, BOB), 5, "allowance is the latest value");
    }

    function test_approve_revertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFrom_spendsAllowance() public {
        token.approve(BOB, 100);
        vm.expectEmit(true, true, false, true);
        emit Transfer(deployer, ALICE, 60);
        vm.prank(BOB);
        assertTrue(token.transferFrom(deployer, ALICE, 60), "transferFrom returned false");
        assertEq(token.balanceOf(ALICE), 60, "alice received");
        assertEq(token.balanceOf(deployer), SUPPLY - 60, "deployer paid");
        assertEq(token.balanceOf(BOB), 0, "the spender received nothing");
        assertEq(token.allowance(deployer, BOB), 40, "allowance decreased by the amount spent");
    }

    function test_transferFrom_infiniteAllowanceIsNotDecremented() public {
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(deployer, ALICE, 1_000);
        assertEq(token.allowance(deployer, BOB), type(uint256).max, "infinite allowance was decremented");
        assertEq(token.balanceOf(ALICE), 1_000, "alice received");
    }

    function test_transferFrom_revertsWithoutAllowance() public {
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, uint256(0), uint256(1))
        );
        token.transferFrom(deployer, ALICE, 1);
    }

    function test_transferFrom_revertsAboveAllowance() public {
        token.approve(BOB, 10);
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, uint256(10), uint256(11))
        );
        token.transferFrom(deployer, ALICE, 11);
        assertEq(token.allowance(deployer, BOB), 10, "a failed transferFrom changed the allowance");
        assertEq(token.balanceOf(deployer), SUPPLY, "a failed transferFrom moved tokens");
    }

    function test_transferFrom_revertsWhenOwnerBalanceInsufficient() public {
        // Alice approves more than she holds; the balance check, not the allowance, stops it.
        token.transfer(ALICE, 5);
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, uint256(5), uint256(6))
        );
        token.transferFrom(ALICE, CAROL, 6);
    }

    function test_transferFrom_revertsToZeroAddress() public {
        token.approve(BOB, 100);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // No admin surface
    // ---------------------------------------------------------------------------------------------

    /// @dev Every common privileged entry point is absent: the call reverts (no fallback), the
    /// supply does not move, and nobody gains a balance. Tried from a stranger and from the deployer.
    function test_noMintOrAdminEntryPoints() public {
        address attacker = address(0xBEEF);
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "setOwner(address)",
            "transferOwnership(address)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "setMinter(address)",
            "upgradeTo(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);

            vm.prank(attacker);
            (bool okAsAttacker,) = address(token).call(data);
            assertFalse(okAsAttacker, signatures[i]);

            (bool okAsDeployer,) = address(token).call(data);
            assertFalse(okAsDeployer, signatures[i]);

            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
            assertEq(token.balanceOf(deployer), SUPPLY, signatures[i]);
        }
    }

    /// @dev The deployer, the most plausibly trusted address, cannot pull a holder's tokens without
    /// an allowance, and the holder can still transfer afterwards.
    function test_deployerCannotMoveOrFreezeAHolder() public {
        token.transfer(ALICE, 1_000);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, uint256(0), uint256(1))
        );
        token.transferFrom(ALICE, deployer, 1);
        assertEq(token.balanceOf(ALICE), 1_000, "the deployer moved a holder's balance");

        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 500), "the holder can no longer transfer");
        assertEq(token.balanceOf(BOB), 500, "the holder's transfer delivered short");
    }

    function test_noEtherAccepted() public {
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "the token accepted ether");
    }

    // ---------------------------------------------------------------------------------------------
    // Bytecode properties the launch floor checks
    // ---------------------------------------------------------------------------------------------

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0, "the token has no runtime code");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                // PUSH1..PUSH32: skip the immediate bytes.
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
            assertTrue(op != 0xF2, "runtime code contains CALLCODE");
            assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
        }
    }

    function test_runtimeCodeWithinEip170() public view {
        assertLe(address(token).code.length, EIP170_LIMIT, "runtime exceeds EIP-170");
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 raw) public {
        vm.assume(to != address(0));
        vm.assume(to != deployer);
        uint256 amount = raw % (SUPPLY + 1);

        assertTrue(token.transfer(to, amount), "transfer returned false");

        assertEq(token.balanceOf(to), amount, "recipient received exactly the amount");
        assertEq(token.balanceOf(deployer), SUPPLY - amount, "sender paid exactly the amount");
        assertEq(token.balanceOf(to) + token.balanceOf(deployer), SUPPLY, "balances do not sum to the supply");
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
    }

    function testFuzz_transferRevertsAboveBalance(uint256 raw) public {
        uint256 held = raw % SUPPLY; // 0 <= held < SUPPLY, so held + 1 cannot overflow
        if (held > 0) {
            token.transfer(ALICE, held);
        }
        uint256 attempt = held + 1;

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, attempt));
        token.transfer(BOB, attempt);

        assertEq(token.balanceOf(ALICE), held, "a failed transfer changed the balance");
        assertEq(token.balanceOf(BOB), 0, "a failed transfer delivered tokens");
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowanceRaw, uint256 spendRaw) public {
        uint256 allowed = allowanceRaw % (SUPPLY + 1);
        uint256 spend = spendRaw % (SUPPLY + 1);
        token.approve(BOB, allowed);

        if (spend <= allowed) {
            vm.prank(BOB);
            assertTrue(token.transferFrom(deployer, ALICE, spend), "transferFrom returned false");
            assertEq(token.balanceOf(ALICE), spend, "alice received exactly the amount");
            assertEq(token.allowance(deployer, BOB), allowed - spend, "allowance decreased by the amount");
        } else {
            vm.prank(BOB);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, allowed, spend)
            );
            token.transferFrom(deployer, ALICE, spend);
            assertEq(token.balanceOf(ALICE), 0, "a failed transferFrom delivered tokens");
            assertEq(token.allowance(deployer, BOB), allowed, "a failed transferFrom changed the allowance");
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
    }

    function testFuzz_approveAnySpender(address spender, uint256 value) public {
        vm.assume(spender != address(0));
        vm.assume(spender != deployer);
        assertTrue(token.approve(spender, value), "approve returned false");
        assertEq(token.allowance(deployer, spender), value, "allowance");
        assertEq(token.balanceOf(spender), 0, "approve moved tokens to the spender");
        assertEq(token.balanceOf(deployer), SUPPLY, "approve moved the deployer's tokens");
    }
}
