# Empirical simulation — what an arbitrary unprivileged caller can reach

Every state-changing function that touches value was simulated via `eth_call`
(no transactions sent) with **`from = 0x1111111111111111111111111111111111111111`**,
an address holding no role, against current BSC state. Revert reasons are decoded
from returned `Error(string)` data. Reproduce with `tools/simulate.py`.

This is the ground truth for "who can actually do what right now", independent of
what the source comments claim.

## TaxProcessor `0xfe03…97D4` (holds XAUt for holders)

| Call | Result | Decoded |
|---|---|---|
| `withdrawAll(XAUt, attacker)` | ❌ REVERT | `Ownable: caller is not the owner` |
| `withdrawAll(quote/native, attacker)` | ❌ REVERT | `Ownable: caller is not the owner` |
| `processTaxTokens(1)` | ❌ REVERT | `TaxProcessor: caller is not the tax token` |
| `setConverter(attacker)` | ❌ REVERT | `Ownable: caller is not the owner` |
| `setReceivers(attacker×3)` | ❌ REVERT | `Ownable: caller is not the owner` |
| `dispatch()` | ✅ **REACHABLE** | succeeds — permissionless keeper; only routes accrued balances to their configured receivers |
| `processBondingCurveTax(1)` | ❌ REVERT | `ERC20: transfer amount exceeds balance` — not access-gated, but pulls quote from the caller, so harmless from an unfunded address |

## Dividend `0x2576…B3cF` (holds XAUt for holders)

| Call | Result | Decoded |
|---|---|---|
| `emergencyWithdraw(XAUt, all, attacker)` | ❌ REVERT | `Ownable: caller is not the owner` |
| `setShare(attacker, huge)` | ❌ REVERT | `Dividend: caller is not the tax token` |
| `excludeAddress(attacker)` | ❌ REVERT | `Ownable: caller is not the owner` |
| `setDividendToken(attacker)` | ❌ REVERT | `Ownable: caller is not the owner` |
| `distributeDividend([])` | ✅ **REACHABLE** | succeeds — permissionless keeper (pushes owed dividends to listed users) |
| `withdrawDividends()` | ✅ **REACHABLE** | succeeds — permissionless self-claim (returns 0 for a holder with no shares) |

## CETS token `0xb0c2…7777` (ownership renounced)

| Call | Result | Decoded |
|---|---|---|
| `startMigration()` | ❌ REVERT | `Ownable: caller is not the owner` |
| `finalizeMigration()` | ❌ REVERT | `Ownable: caller is not the owner` |

Because the token's owner is `0x0`, every `onlyOwner` function on the token is
**permanently uncallable** by anyone — the tax parameters, pool set, and state
machine are frozen as configured.

## What this establishes

- **No unprivileged caller can move, mint, or redirect holder funds.** Every sweep
  / reconfigure / share-mint path reverts with an ownership or caller check.
- The only value functions an anonymous caller can reach are **keeper/claim**
  functions (`dispatch`, `distributeDividend`, `withdrawDividends`) that move funds
  only to their already-configured, rightful recipients.
- **The real authority is `onlyOwner` = the Portal**, and the Portal's admin is the
  launchpad Safe `0x1f96…8A3b`. That is the address whose compromise would convert
  these reverts into a drain — not any bug reachable from outside. The sweep
  functions themselves are honest about their gate; the risk is concentration of
  the gate, documented in `../UNRESOLVED.md`.
