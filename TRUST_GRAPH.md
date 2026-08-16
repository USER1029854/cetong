# CETS trust graph — the map

This is the map an auditor reads first. It explains the whole contract graph around
the target in both directions and points to where each contract's code lives in this
repo. Every contract named here is saved as real, readable code (or, for the one
unverified implementation, as recovered behavior). If it is named, it is in the repo.

- **Target:** `0xb0c2ab5af4028461ace3f6e1c33a4ee1404e7777` — "Cets On Gold" (CETS), BSC
- **What it is:** an EIP-1167 clone of **FlapTaxTokenV3**, a token from the **Flap
  launchpad**. 3% buy/3% sell tax, liquidated to **Tether Gold (XAUt)** and paid to
  holders as dividends.
- **Graph size:** 20 contracts + 9 EOA/off-chain actors. This is a small, complete
  graph — a token, a pool, two fund helpers, the launchpad that owns them, and the
  canonical DEX/Safe infrastructure underneath. It resolves fully; it is not
  truncated.

```
                         UPSTREAM (authority — what can drain/re-rule the target)
                         ─────────────────────────────────────────────────────────
   Launchpad-admin Safe 0x1f96…8A3b  (3-of-4 SafeL2 v1.4.1)
        │   holds DEFAULT_ADMIN_ROLE on Portal  ─────────────┐
        │   owns ProxyAdmin 0xB248…9bD4 (can UPGRADE Portal) │
        ▼                                                     ▼
   Portal proxy 0xe2cE…9De0  ──impl──▶  Portal 0x1533…b74f  (Flap launchpad)
        │  is owner() of ↓↓                (AccessControl: DEFAULT_ADMIN/AUDITOR/GUARDIAN)
        │
        │      ┌───────────────────────────────────────────────────────────┐
        ▼      ▼                                                            │
   TaxProcessor 0xfe03…97D4          Dividend 0x2576…B3cF                   │
   (clone→0x8863…7d40)              (clone→0xcc11…0d71)                     │
        ▲   onlyOwner: withdrawAll        ▲  onlyOwner: emergencyWithdraw   │
        │                                 │                                 │
   ═════╪═════════════════════════════════╪═════════════════════════════════╪═══════
        │                TARGET           │                                 │
        │                                 │                                 │
   CETS token 0xb0c2…7777  (clone→ FlapTaxTokenV3 0x024f…6422) ─────────────┘
        │  _processTax → TaxProcessor.processTaxTokens (onlyTaxToken)
        │  _afterTokenTransfer → Dividend.setShare (onlyTaxToken)
        ▼
                         DOWNSTREAM (what the target leans on)
                         ─────────────────────────────────────
   quoteToken/dividendToken:  XAUt 0x21cA…A3bf (proxy) ──impl──▶ 0x9151…EcC5 (Tether Gold OFT, upgradeable by Tether)
   mainPool:                  PancakePair CETS/XAUt 0xdabb…7489  (canonical, CREATE2-proven)
   v2Router:                  PancakeRouter 0x10ED…024E  →  PancakeFactory 0xcA14…0c73,  WBNB 0xbb4C…095c
   swapRegistry (immutable):  0x644A…BEB6 (proxy) ──impl──▶ 0x9a68…7a65  (UNVERIFIED; INACTIVE for CETS)
   feeReceiver:               Safe 0x8a08…aB0E (3-of-4)      marketAddress: EOA 0xcE27…5b18      burn: 0xdead
```

## The two directions, in words

### Downstream — everything the target leans on

| # | Contract | Address | Why it's in the graph | Code |
|---|---|---|---|---|
| 1 | FlapTaxTokenV3 (impl) | `0x024f…6422` | the code the CETS clone runs | `contracts/00-target/FlapTaxTokenV3_impl/` |
| 2 | TaxProcessor | `0xfe03…97D4` → `0x8863…7d40` | token approves & calls it to liquidate tax; **holds XAUt** | `contracts/10-downstream/TaxProcessor*/` |
| 3 | Dividend | `0x2576…B3cF` → `0xcc11…0d71` | token calls `setShare`; **holds XAUt** owed to holders | `contracts/10-downstream/Dividend*/` |
| 4 | XAUt (Tether Gold) | `0x21cA…A3bf` → `0x9151…EcC5` | the quote & dividend asset; every value figure depends on it | `contracts/10-downstream/XAUt_*/` |
| 5 | PancakePair CETS/XAUt | `0xdabb…7489` | the pool tax sells into; price source | `contracts/10-downstream/PancakePair/` |
| 6 | PancakeRouter | `0x10ED…024E` | TaxProcessor swaps/adds-liquidity through it | `contracts/10-downstream/PancakeRouter/` |
| 7 | PancakeFactory | `0xcA14…0c73` | created the pair; router reads it | `contracts/10-downstream/PancakeFactory/` |
| 8 | WBNB | `0xbb4C…095c` | weth of the system / router intermediary | `contracts/10-downstream/WBNB/` |
| 9 | SwapRegistry | `0x644A…BEB6` → `0x9a68…7a65` | immutable in TaxProcessor; **inactive** for CETS; impl **unverified** | `recovered-behavior/SwapRegistry.md` |
| 10 | MultiDexRouter | `0xDedF…99ec` | router the SwapRegistry would use (Case 3, inactive) | `contracts/30-peripheral/MultiDexRouter/` |

**How value flows.** A buy or sell against the pool triggers the token's `_transfer`,
which skims 3% to the token itself. When accrued tax crosses the dynamic
`liquidationThreshold` and someone transfers *to* the pool, `_liquidateTax` →
`_processTax` approves the TaxProcessor and calls `processTaxTokens`. The
TaxProcessor swaps CETS→XAUt on PancakeSwap (**`amountOutMin` hard-coded to 0** — see
`TaxProcessorUniV2.sol:85`), splits the XAUt into fee/market/LP/dividend parts, adds
one-sided liquidity (LP → `0xdead`), and forwards the dividend part to the Dividend
contract, which books it per-share. Holders later pull XAUt via `withdrawDividends`.

### Upstream — what holds power over the target without being it

| # | Authority | Address | Power it holds | Code |
|---|---|---|---|---|
| A | **Launchpad-admin Safe** | `0x1f96…8A3b` | **the top of everything**: DEFAULT_ADMIN_ROLE on the Portal *and* owner of the Portal's ProxyAdmin | `contracts/20-upstream/Safe_LaunchpadAdmin/` |
| B | Portal (proxy+impl) | `0xe2cE…9De0` → `0x1533…b74f` | `owner()` of TaxProcessor & Dividend → gates every sweep/reconfigure | `contracts/20-upstream/Portal_*/` |
| C | ProxyAdmin (Portal) | `0xB248…9bD4` | can swap the Portal implementation for arbitrary logic | `contracts/20-upstream/ProxyAdmin_Portal/` |
| D | Fee-receiver Safe | `0x8a08…aB0E` | receives protocol fee share (3-of-4, shares 3 signers with A) | `contracts/20-upstream/Safe_FeeReceiver/` |
| E | XAUt proxy admin | `0xedaba0…B027` | Tether's key; can upgrade the gold token itself | (external — see `UNRESOLVED.md`) |
| F | SwapRegistry ProxyAdmin | `0x830C…9d95` → EOA `0x8187F1…` | single EOA can upgrade the shared registry (off CETS path) | `contracts/20-upstream/ProxyAdmin_SwapRegistry/` |

**The one that matters most.** The token itself is renounced and honest — but that is
the least interesting part. The XAUt that actually belongs to holders sits in the
**Dividend** and **TaxProcessor** contracts, whose `emergencyWithdraw`/`withdrawAll`
are `onlyOwner`, and whose owner is the **Portal**, which is controlled — by role and
by upgradeability — by a single **3-of-4 launchpad Safe** (`0x1f96…8A3b`). That Safe,
or a Portal upgrade it authorizes, is the real drain path. This is the classic shape:
a flawless-looking token, drained through a separate contract that holds authority
over its funds. See `live-state/simulation-unprivileged.md` for the empirical proof
that *only* that owner path can move the funds.

## Shared-codebase note (platform-wide, not CETS-specific)

CETS is an EIP-1167 clone of `FlapTaxTokenV3`, and its TaxProcessor/Dividend are
clones of the Flap platform implementations. The two properties above —
(1) `amountOutMin = 0` in tax liquidation and (2) `onlyOwner` sweep functions whose
owner is the Portal Safe — are **implementation-level and shared by every token the
Flap launchpad has deployed from these implementations**, not unique to CETS. An
auditor reasoning about CETS is really reasoning about the Flap template.

## Where to read each piece

- **Source of everything:** `contracts/` (tiered `00-target` / `10-downstream` /
  `20-upstream` / `30-peripheral`; each dir has the full Etherscan source tree +
  `_etherscan_meta.json` with compiler settings, or a `README.md` for shells).
- **The one unverified impl:** `recovered-behavior/SwapRegistry.md`.
- **Current chain reality:** `live-state/live-state.md` (+ `.json`).
- **Who can actually do what:** `live-state/simulation-unprivileged.md`.
- **Are the dependencies genuine:** `integrity/integrity-report.md`.
- **What's still open (incl. off-chain):** `UNRESOLVED.md`.
