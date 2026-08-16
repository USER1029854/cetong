# Live on-chain state — CETS trust graph

Snapshot pinned at **BSC block 116,212,059** (timestamp 1786856140 ≈ 2026-08-16).
Machine-readable source of truth: [`live-state.json`](./live-state.json). Regenerate
with `tools/capture_livestate.py`.

Everything below is *current chain reality*, not what the code implies. Values move
block to block; the JSON is the pinned snapshot.

## Proxy / clone resolution (what each shell actually points to now)

| Shell | Kind | Resolves to (live) | Who can change the target |
|---|---|---|---|
| CETS `0xb0c2…7777` | EIP-1167 clone | impl `0x024f…6422` (FlapTaxTokenV3) | immutable (clone target is fixed in bytecode) |
| TaxProcessor `0xfe03…97D4` | EIP-1167 clone | impl `0x8863…7d40` | immutable |
| Dividend `0x2576…B3cF` | EIP-1167 clone | impl `0xcc11…0d71` | immutable |
| XAUt `0x21cA…A3bf` | TransparentUpgradeableProxy | impl `0x9151…EcC5` | proxy admin `0xedaba0…B027` (Tether) |
| Portal `0xe2cE…9De0` | TransparentUpgradeableProxy | impl `0x1533…b74f` | ProxyAdmin `0xB248…9bD4` → Safe `0x1f96…8A3b` |
| SwapRegistry `0x644A…BEB6` | TransparentUpgradeableProxy | impl `0x9a68…7a65` (unverified) | ProxyAdmin `0x830C…9d95` → EOA `0x8187F1…` |

Clones are immutable (the implementation is hard-coded in the 45-byte EIP-1167
shell). The **upgradeable** pieces are XAUt (Tether-controlled), the Portal
(launchpad-Safe-controlled), and the SwapRegistry (EOA-controlled, but off CETS's
active path).

## The pool — reserves vs. real balances (honesty check)

| | XAUt side (6 dec) | CETS side (18 dec) |
|---|---|---|
| `getReserves()` | 40.467988 | 18,440,279.898 |
| `balanceOf(pair)` | 40.467988 | 18,440,279.898 |
| **Match?** | ✅ | ✅ |

`reserves_match_balances = true` — the pool's cached reserves equal its real token
balances, so there is no un-synced donation / skim imbalance staged against it at
this block. Quote asset is real Tether Gold (XAUt, 6 decimals, `name()="Tether
Gold"`). LP supply is 0.0244 and effectively all LP was sent to `0xdead` at
liquidity provision (see TaxProcessor `_addLiquidity` → `DEAD_ADDRESS`).

## Token tax configuration (live)

| Field | Value |
|---|---|
| state | `2` = **TaxEnforcedAntiFarmer** |
| buy tax | 300 bps (3.0%) |
| sell tax | 300 bps (3.0%) |
| liquidationThreshold | 380,396 CETS (dynamic; floor 50,000 / ceiling 400,000) |
| taxExpirationTime | 4939590216 → **year ~2126** (tax effectively never auto-expires) |
| antiFarmerExpirationTime | 1788582216 → **~2026-09-05** (anti-farmer window still open; then → TaxEnforced) |
| owner | `0x0` (**renounced** — `startMigration`/`finalizeMigration` permanently dead) |
| CETS accrued as tax on token, awaiting liquidation | 285,573 CETS (< threshold, so no liquidation pending) |
| CETS burned to `0xdead` | 45,578,077 (~4.56% of supply) |

Note `taxExpirationTime` is ~100 years out, so the "time-dependent tax that
automatically removes itself" never practically expires for CETS. After the
anti-farmer window it narrows from "all pools" to "mainPool only".

## Funds held on behalf of holders (the sweep surface)

| Holder contract | XAUt held now | owner (can sweep) |
|---|---|---|
| Dividend `0x2576…B3cF` | **0.885858 XAUt** (undistributed dividends owed to holders) | Portal `0xe2cE…9De0` |
| TaxProcessor `0xfe03…97D4` | 0.006344 XAUt (dust in-transit) | Portal `0xe2cE…9De0` |

- Dividend `totalShares` = 930,714,645 CETS across eligible holders (min balance
  10,000 CETS to be eligible).
- TaxProcessor `totalDividendTokenSent` (lifetime) = **49.41 XAUt** routed to the
  Dividend contract so far.
- The instantaneous sweepable balance is small (~0.89 XAUt), but the owner can also
  **redirect all future dividend flow** via `setReceivers`/`setDividendToken`
  (`onlyOwner`) and sweep whatever accrues. The risk is a standing capability, not
  the current balance.

## Standing approvals

| Approval | Value | Note |
|---|---|---|
| CETS: token → TaxProcessor | `type(uint256).max` | self-approve so the processor can pull accrued tax; expected |
| CETS: TaxProcessor → router | 0 | set transiently to `amount` during a swap via `safeApprove`, reset to 0 after |
| XAUt: TaxProcessor → router | 0 | same transient pattern |

No unexpected standing allowances to third parties.

## Authorities (live)

| Role | Holder |
|---|---|
| TaxProcessor.owner / Dividend.owner | Portal proxy `0xe2cE…9De0` |
| Portal DEFAULT_ADMIN_ROLE | Safe `0x1f96…8A3b` (**confirmed on-chain: `hasRole(0x00, Safe)=true`**) |
| Portal upgrade (ProxyAdmin owner) | Safe `0x1f96…8A3b` |
| Launchpad-admin Safe | 3-of-4 multisig (`SafeL2` v1.4.1) |
| TaxProcessor.feeReceiver | Safe `0x8a08…aB0E` (3-of-4, `GnosisSafeL2` v1.3.0) |
| TaxProcessor.marketAddress | EOA `0xcE2759…5b18` |
| XAUt upgrade | `0xedaba0…B027` (Tether) |

See [`../TRUST_GRAPH.md`](../TRUST_GRAPH.md) for how these connect and
[`../UNRESOLVED.md`](../UNRESOLVED.md) for the off-chain pieces behind them.
