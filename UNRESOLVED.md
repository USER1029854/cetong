# UNRESOLVED — what an auditor must not assume is safe

Everything in `contracts/` is read or recovered. This file lists what genuinely
could **not** be pinned down, and — for each — the specific question it leaves open
and whatever on-chain evidence bounds it. Read this before concluding anything.

Nothing here blocks reading the code; each item is a place where the code alone does
not tell the whole truth.

---

## A. Off-chain components in the trust path

These have no bytecode to read and no address to simulate. They are named, their
decision is stated, and their observable on-chain behavior is cited.

### A1. The launchpad-admin Safe signers — the top of all authority
- **Who:** the 4 EOAs owning Safe `0x1f96BC88f0794060433Be5F3EC9159a9C4f08A3b`
  (`0xA85c06…34Ec`, `0x29a649…b491`, `0x01db37…D845`, `0x705163…D1c2`), 3-of-3
  threshold-of-4.
- **What they control:** DEFAULT_ADMIN_ROLE on the Portal **and** the Portal's
  ProxyAdmin. Between the two, they can reconfigure or **upgrade the Portal to
  arbitrary logic**, and the Portal is `owner()` of the TaxProcessor and Dividend
  whose `withdrawAll`/`emergencyWithdraw` are `onlyOwner`. **Three of these four keys
  acting together can drain the XAUt held for holders and redirect all future tax
  proceeds.**
- **What would go wrong if compromised:** total loss of holder dividend funds and
  capture of the tax stream — for CETS and for every other Flap token, since the same
  Safe sits over the whole launchpad.
- **On-chain evidence gathered:** threshold = 3, four distinct signer EOAs, Safe
  `nonce` = 77 (an actively-used operational multisig, not a dormant deployer). Three
  of its four signers are the same EOAs that own the fee-receiver Safe
  `0x8a08…aB0E` — i.e. one team, two multisigs, overlapping keys.
- **Open question:** are these four keys held by independent people/HSMs, or by one
  operator? Off-chain; not determinable from the chain. Treat the launchpad as a
  trusted-operator system, not a trustless one.

### A2. XAUt / Tether — the gold backing and its freeze/upgrade authority
- **Who:** Tether, via XAUt proxy admin `0xedaba024…CccB027` (a `ProxyAdmin`
  contract, Tether-controlled) and the token's own blacklist/mint logic in
  `TetherTokenOFTExtension`.
- **What they control:** whether XAUt is redeemable for real gold, and whether any
  address (including this system's pool, TaxProcessor, or Dividend) can be
  **blacklisted/frozen**, plus the ability to **upgrade the XAUt implementation**.
- **What would go wrong:** if Tether blacklists the pool or the fund contracts, or
  de-pegs/halts redemption, the "gold-backed dividend" loses backing regardless of
  this project's code. This is an external dependency the project's code silently
  assumes is honest.
- **On-chain evidence:** XAUt is the genuine Tether Gold OFT (verified impl,
  `name()="Tether Gold"`, 6 decimals) — see `integrity/integrity-report.md`. The
  blacklist and upgrade functions are Tether's, external to this repo.
- **Open question:** none resolvable here — Tether's operational policy is off-chain.

### A3. The Flap keeper / backend that drives `dispatch()` and dividend distribution
- **Who:** unknown off-chain caller(s). `TaxProcessor.dispatch()` and
  `Dividend.distributeDividend()` are **permissionless** (proven reachable from an
  unprivileged address in `live-state/simulation-unprivileged.md`), so in practice a
  Flap backend keeper calls them on a schedule.
- **What it controls:** the *timeliness* of pushing accrued XAUt to holders. It does
  **not** control custody — holders can always self-claim via
  `withdrawDividends()` (also proven permissionless), so a silent keeper delays but
  cannot steal.
- **On-chain evidence:** `totalDividendTokenSent` = 49.41 XAUt has actually flowed to
  the Dividend contract over the pool's life, so the distribution machinery has been
  exercised, not merely declared.
- **Open question:** the keeper's identity/liveness policy is off-chain; low severity
  because self-claim exists.

### A4. MEV searchers on tax liquidation (adversarial off-chain actor)
- **What:** `TaxProcessorUniV2._swapTokensForQuote` calls PancakeSwap with
  `amountOutMin = 0` (`contracts/10-downstream/TaxProcessorUniV2_impl/src/Tax/TaxProcessorUniV2.sol:85`)
  and `_addLiquidity` with `0/0` mins. Every liquidation is sandwichable by any
  off-chain MEV bot; value that should become holder gold leaks to searchers.
- **On-chain evidence:** the swap path and `amountOutMin=0` are in verified source;
  the liquidation trigger is on-chain and automatic (no privileged actor needed).
- **This is not a hole in the map** — it is fully readable in code and named here so
  the audit weighs the off-chain adversary, not a trusted party.

### A5. Token metadata (`metaURI`)
- IPFS CID `bafkreif65qoykgcxlpxssfywyb3yq4pwr6zvbgijoeax5t6nqpjyqwzyyq` — off-chain
  name/image. Not trust-critical to funds; named for completeness.

---

## B. Contracts / code not fully resolved

### B1. SwapRegistry implementation — unverified source
- `0x9a681bC1350636BBf81085207cde7485dAa67a65` (behind proxy `0x644A…BEB6`).
- **Status:** source not verified. Behavior recovered (24/31 selectors matched to the
  known `ISwapRegistry` interface; live config read out) — see
  `recovered-behavior/SwapRegistry.md`.
- **Residual unknowns:** 3 selectors (`0x398102a4`, `0x7353f3af`, `0xbc9589fd`) could
  not be named; they are read paths. The full impl source is not available.
- **Bounding fact:** **inactive for CETS** — the TaxProcessor only touches the
  registry when `dividendToken != quoteToken`, but for CETS both are XAUt. It moves
  no CETS value today. It would activate only if the Portal (owner) called
  `setDividendToken` to a third token.
- **Platform concern:** the registry's ProxyAdmin owner is a **single EOA**
  (`0x8187F13ed6C7C9554AfE4Dd4C4D4960174846063`), so one key can upgrade this shared
  registry. Off CETS's active path, but a platform-level single point of trust.

### B2. Portal internal module graph — bounded on purpose
- The Portal (`0x1533…b74f`, full verified source in `contracts/20-upstream/Portal_impl/`)
  is a large modular launchpad that `delegatecall`s to many module implementations
  (launchers, migrators, V4 hooks, a trade module, a vault portal). Their addresses
  live in the Portal's bespoke packed/SSTORE2 storage, not in simple public getters.
- **Why not fully enumerated:** these modules are **launchpad-platform internals, one
  hop beyond CETS's direct fund-control path**, which is already fully captured (Portal
  owns the fund contracts; the launchpad Safe controls the Portal). Enumerating and
  resolving every Portal module would expand the graph into the entire Flap platform
  rather than CETS's surface.
- **What the audit has:** the complete Portal source is in the repo and readable; a
  reviewer wanting to extend into launchpad internals can enumerate the module
  addresses from that source + the Portal's storage. This edge is stated, not
  silently dropped.
- **Relevance to CETS:** the launchpad Safe could, via a Portal upgrade, introduce a
  new path to the owned fund contracts — which is already the worst case captured in
  item A1. So the un-enumerated modules do not widen CETS's worst case.

### B3. Exact CETS token deploy timestamp
- Could not be pinned: BSC `getcontractcreation` and `getLogs` are blocked on the
  free Etherscan V2 tier for this chain, and the public RPCs used do not expose an
  archive index for a cheap creation lookup.
- **Bounding facts:** the PancakePair was created 2026-08-06 (per the discovery
  step); the token's `poolState` is in `TaxEnforcedAntiFarmer` with
  `antiFarmerExpirationTime` = 1788582216 (≈2026-09-05) and a 30-day
  `antiFarmerDuration`, consistent with a late-July/early-August 2026 migration.
- **Open question:** exact block/timestamp of the token clone deployment.

---

## C. Authorities that are contracts but resolve to off-chain keys

| Authority | Resolves to | Note |
|---|---|---|
| Portal ProxyAdmin `0xB248…9bD4` | owner = launchpad Safe `0x1f96…8A3b` | see A1 |
| SwapRegistry ProxyAdmin `0x830C…9d95` | owner = **EOA** `0x8187F1…` | single key; off CETS path (B1) |
| `marketAddress` `0xcE27591a…5b18` | **EOA** | receives only the market-fee share of processed tax; unconstrained externally-owned wallet, but cannot reach principal |
| XAUt ProxyAdmin `0xedaba0…B027` | Tether-controlled | see A2 |

---

### One-line severity read (for navigation only — this repo does not assess exploitability)

The graph's worst case is **A1**: a 3-of-4 launchpad multisig sits above the
contracts that hold holders' XAUt and can drain or re-rule them, for CETS and every
Flap token alike. Everything else is either inactive for CETS (B1), external
infrastructure (A2), permissionless-but-custody-safe (A3), an off-chain adversary
already visible in code (A4), or a deliberately-stated graph boundary (B2).
