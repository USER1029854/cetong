# Unresolved / residual-risk register

Everything that could bear on HYDX's security but that this repo could **not** fully resolve to
readable, reasoned-about code — plus the deliberate scoping boundaries. Each item says what it might be
hiding. "Resolved" items (source saved, behavior recovered, authority pinned) are in the README and
`live-state/`; this file is only the residue.

Legend: 🟥 genuinely opaque · 🟧 off-chain (no bytecode to read) · 🟨 pinned to a single key / custody
unknown · ⬜ deliberately out of scope (with rationale) · 🟩 noted, assessed low.

---

## 🟥 Unverified contracts in the value path
- **MevX Executor impl `0x9e904666…`** and **MevX Router impl `0x2c3baec4…`** (behind proxies
  `0x3a980817…` / `0xb32f9894…`) — the only source-unverified logic contracts reached from the pool's
  plugin. Recovered behavior (selectors, guards, simulation from an unprivileged caller) is in
  [`recovered/`](./recovered/). **What they might hide:** how the MEV subsystem interacts with swaps on
  the $460K pool and where captured value flows. See `recovered/` for how far analysis got and what, if
  anything, still resists it.
- The plugin **beacon `0x106937fc…`** and **beacon-proxy shell `0xe33a2429…`** are unverified but are
  standard OZ `UpgradeableBeacon` / `BeaconProxy` (confirmed in `recovered/`); their only power is the
  upgrade pointer, whose owner is named in `live-state/AUTHORITIES.md`.

## 🟧 Off-chain components in the trust path (cannot be resolved on-chain — see `live-state/OFFCHAIN.md`)
- **Gauge-eligibility updater** EOA `0x40fbfe53…` — decides which pools may get permissionless gauges.
  Evidenced (13 `setPoolEligibility` calls, latest 2026-06-10). **Hides:** future eligibility decisions;
  a compromised key misdirects emissions (bounded — no mint/drain).
- **Protocol operator key** (7702 EOA `0xdead1f5a…`) — the single highest-leverage off-chain key: it can
  administer the pool and **swap the plugin hook logic for every Hydrex pool** on its own. **Hides:** the
  off-chain process/custody behind a single key with protocol-wide hook-code control.
- **MevX MEV keeper** (7702 EOA `0x00000007ac13…`) — **active**; back-runs swaps via the plugin's
  `afterSwap` using its own capital, with a fee-free swap privilege. **Hides:** MEV routing/pricing; it
  cannot touch reserves. Its executor/router impls are the unverified contracts above.
- **ALM rebalance keeper** — **currently inactive** (`rebalanceManager = 0`); a latent role that
  `0xdead1f5a…` can activate. Listed as a watch item, not a live component.
  On-chain authenticating addresses and guardrails for all three: [`live-state/liquidity-analysis.md`](./live-state/liquidity-analysis.md).
- **Multisig signer key custody** — 5 EOAs (`0x813f…`, `0xb4d2…`, `0xea1b…`, `0x35e8…`, `0x7426…`) behind
  the Admin/Treasury/Floor/Proposer Safes. **Hides:** whether keys are independently held by distinct,
  honest parties. All protocol power ultimately reduces to this.
- **`emissionsGovernor` is currently `address(0)`** (inactive). If ever set, it becomes an off-chain
  vote-driven input to emissions. Watch item.

## 🟨 Authorities pinned to a single EOA (custody off-chain)
- **AlgebraFactory owner** = bare EOA `0x74266f2b…` (also a signer on the 3-of-3 Proposer Safe). Single
  key controlling the DEX factory + several Voter/feeDist registry roles. What it can do to the existing
  pool: see `live-state/liquidity-analysis.md`.
- **MevX `ProfitDistributor.owner`** = vanity EOA `0x000000077ac13a2fc7c7a154d28e6251a5e4648b` (EIP-7702).
- **AlgebraFactory `POOLS_ADMINISTRATOR` #2** = vanity EOA `0xdead1f5af792afc125812e875a891b038f888258`
  (EIP-7702). An EOA holds a pool-administration role on the factory.

## ⬜ Deliberately out of scope (with rationale — these do not hold power over HYDX)
- **Third-party HYDX trading pools** (dozens: HYDX/PING, HYDX/blarp, HYDX/KIBBLE, HYDX/OPENX, HYDX/WETH
  on UniV3/V4/AlienBase, etc.). They hold small HYDX amounts but cannot mint, move, or drain the target
  or its main pool; draining any of them harms only that pool's own LPs. **Not saved.** The Hydrex-native
  pools that matter (main Algebra HYDX/USDC, classic Solidly HYDX/USDC) are fully reproduced.
- **Individual gauge instances.** The gauge *factory*, the delegatecall *gaugeLogic*, and one sample
  gauge (`0x243b6136…`) are saved; the per-pool gauge clones are not individually reproduced. Gauges
  receive emissions and distribute to LPs; they hold no authority over HYDX.
- **Deep Algebra DEX plumbing not touching the main pool** (full FarmingCenter internals, custom-pool
  deployer paths, second SecurityRegistry). Saved as source where reached, but not behaviorally
  simulated end-to-end.
- **The Hydrex perpetuals engine.** "DEX/perp" notwithstanding, no perp/clearing/margin/settlement
  contract holds any on-chain role over HYDX, the Minter, the pools, or the registries (scanned; none
  found). It is a separate deployment that, if it exists, uses HYDX only as a traded asset. Out of this
  token's authority graph.

## 🟩 Noted, assessed low
- **`ProxyAdmin.sol` modification** — a benign added `constructor(initialOwner)` vs OZ 4.8.3 (integrity
  finding). Upgrade functions retain original `onlyOwner`; no weakened check. Diff:
  `integrity/diffs/ProxyAdmin.diff`.
- **Bespoke Solidly-family `Pair` / `BribeV2`** — no clean upstream to diff against; the Pair's `_k`
  invariant and swap were spot-checked as canonical Solidly (see `integrity/README.md`).
- **USDC** is Circle's canonical, upgradeable, blacklist-capable token — a trusted external, not Hydrex
  code; its Circle-side upgrade authority is out of Hydrex's control by design.

## Tooling limitations
- Etherscan V2 **free tier blocks the `account` (tx-history) module for Base**; historical evidence
  (e.g. the eligibility-updater call log) was gathered from **Blockscout** instead. Exhaustive historical
  tracing of every past upgrade/admin action was not performed.
