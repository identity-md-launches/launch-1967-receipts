# RECEIPTS (RCPTS)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum.

| Parameter | Value |
|---|---|
| Solidity contract | `ReceiptsToken` (`src/ReceiptsToken.sol`) |
| `name()` | `RECEIPTS` |
| `symbol()` | `RCPTS` |
| `decimals()` | 18 |
| Total supply | 1,000,000,000 RCPTS |
| Total supply in minor units | `1000000000000000000000000000` (1e27) |
| Constructor arguments | none |
| Minted to | `msg.sender` of the constructor, once, in the constructor |
| Owner / admin | none |
| Compiler | solc 0.8.26, optimizer on (200 runs), EVM `cancun`, `bytecode_hash = "none"` |

## What the token does

`ReceiptsToken` inherits a plain ERC-20 (`src/ERC20.sol`) that follows the semantics of
OpenZeppelin Contracts v5 `ERC20`:

- `transfer`, `transferFrom`, `approve`, `allowance`, `balanceOf`, `totalSupply`, `name`,
  `symbol`, `decimals`, with the `Transfer` and `Approval` events.
- Failures revert with the ERC-6093 custom errors (`ERC20InsufficientBalance`,
  `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`, `ERC20InvalidSpender`, ...).
- Zero-value transfers are allowed. Transfers to the zero address revert. An allowance of
  `type(uint256).max` is treated as infinite and is not decremented.

It deliberately has nothing else:

- **No mint path after the constructor.** `_mint` is internal and is called exactly once. The
  supply can never grow.
- **No burn, pause, blocklist, freeze, seize or ownership.** No address, the deployer included,
  can move or freeze a holder's balance without an ERC-20 allowance from that holder.
- **No fee, tax or reflection.** Every transfer moves exactly the amount requested, so the
  launch flows (factory to MerkleDistributor, pool seed through the Uniswap v4 PoolManager,
  swaps in either direction) arrive whole without any exemption list.
- **No `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`**, no proxy, no external calls, no
  `receive`/`fallback` (ether sent to it reverts).

## Launch parameters (decided by the launch, recorded here for reference)

These come from the IdentityMD launch and are written into `launch.json` by the manifest step
after this work is accepted. They are not configurable in the contract.

| Item | Value |
|---|---|
| Chain | Ethereum mainnet (chain id 1) |
| Deployer | IdentityMD ProjectFactory via `launchCustom`; the constructor's `msg.sender`, so it receives the whole supply |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Pool fee | 12500 (1.25%) |
| Tick spacing | 60 |
| Swarm share | 10% of the supply, sent by the factory to the launch's MerkleDistributor |
| Pool seed | 88% of the supply (`poolBps` 8800), single-sided, opening at a 2,500 IMD market cap for the whole supply (`initialMarketCapWei` `2500000000000000000000`) |
| Remainder | 2% of the supply to `0x0f44a55663e888bb63618a0c31b68cbc6c01aa71` (`remainderTo`) |

The manifest's `token` entry should read: `contract` `ReceiptsToken`, `name` `RECEIPTS`,
`symbol` `RCPTS`, `decimals` `18`, `constructorArgs` `[]`,
`totalSupply` `"1000000000000000000000000000"`. There are no application contracts.

## Assumptions

- The brief asks for a plain token: name, symbol, supply, all minted once to the deployer. No
  tax, burn, vesting, governance or admin was requested, so none was added. Adding any later
  means a new launch; this contract is immutable.
- The "deployer" is whoever runs the constructor. In tests that is the test contract or a probe
  contract; on the launch it is the ProjectFactory. The token does not special-case any address.
- The ERC-20 base is written into this repository rather than vendored from OpenZeppelin so the
  project has no dependency to fetch and compiles offline. It mirrors OpenZeppelin v5 behaviour
  function for function; it is not OpenZeppelin's audited bytecode.
- `evm_version` is pinned to `cancun`, the newest EVM version solc 0.8.26 knows; the bytecode
  runs unchanged on Ethereum's current fork.

## After launch

Nothing to configure. The token has no owner-settable values, no roles and no setters.

## Operational responsibilities

- **IdentityMD deployer / factory**: deploys the token, forwards the swarm's 10% to the
  MerkleDistributor, seeds the pool with 88%, forwards 2% to `remainderTo`. Source verification
  on the block explorer (`forge verify-contract`, compiler 0.8.26, optimizer 200 runs, EVM
  cancun, `bytecode_hash = "none"`) belongs to the deployer after launch.
- **Requester**: custody of the `remainderTo` wallet and whatever it receives. There is no admin
  key to protect because there is no admin.
- **Holders**: standard ERC-20 self-custody. Approvals are the only way another address can move
  a holder's tokens; grant exact amounts rather than `type(uint256).max` where possible.
- **Nobody** can pause, mint, freeze or recover tokens. Tokens sent to the zero address are
  rejected; tokens sent to any other wrong address are unrecoverable.

## Security review notes (eth-security checklist)

| Checklist item | Status |
|---|---|
| Access control | No privileged functions exist, so nothing to restrict. Verified by `test_noMintOrAdminEntryPoints`. |
| Pausable trade-off | Not pausable by design: no single key can freeze holders. |
| Reentrancy | No external calls, no ether handling. |
| Decimals | 18, constant, matches the manifest. |
| Integer math | Only additions/subtractions guarded by explicit checks; `unchecked` blocks are commented with the invariant that makes them safe. |
| Input validation | Zero-address sender, receiver, approver and spender revert with ERC-6093 errors. |
| Events | `Transfer` on every balance change including the mint, `Approval` on every `approve`. |
| Infinite approvals | Supported for compatibility (ERC-20 norm), documented above as a holder responsibility. |
| Proxy / delegatecall / selfdestruct | None; `test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct` scans the runtime bytecode. |
| Supply growth | Impossible after the constructor; no `mint` selector responds. |
| Automated analysis | Foundry unit and fuzz tests only; Slither/Mythril were not available in this environment. |
| Independent review | Tests are not an audit. An independent adversarial review before release is still recommended, although this token holds no user funds beyond balances. |

## Layout

```
foundry.toml                 compiler pins (solc 0.8.26, bytecode_hash none, no ffi, no fs access)
src/ReceiptsToken.sol        the token
src/ERC20.sol                the ERC-20 base (OpenZeppelin v5 semantics, self-contained)
src/interfaces/              IERC20, IERC20Metadata, IERC20Errors
test/ReceiptsToken.t.sol     unit, failure and fuzz tests
test/support/Vm.sol          the cheatcodes the tests use (no forge-std dependency)
test/support/TestBase.sol    reverting assertions
```

## Build and test

```
forge build
forge test
forge fmt --check
```

The tests read no environment variables and do not depend on the calling address, so they run in
any order and in parallel. Fuzz tests bound their inputs arithmetically instead of rejecting
them, so any seed (including the verifier's `FOUNDRY_FUZZ_SEED`) runs the same number of cases.

A manual deployment outside the IdentityMD launch needs no arguments:

```
forge create src/ReceiptsToken.sol:ReceiptsToken --rpc-url <rpc> --private-key <key>
```

The account that sends that transaction receives the whole supply.
