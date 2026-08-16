# CETS security audit — attacker's-eye review

**Question asked:** can an unprivileged attacker take value or seize control they
weren't entitled to, derived from how this system actually moves money and grants
power? **Verdict: no qualifying finding.** After a mechanical enumeration of the entire
externally-reachable surface and a systematic pass over the state-dependency
compositions, I found no unprivileged path that yields disproportionate economic gain,
and no unauthorized reach to funds or control. This is a *complete* negative result,
not a value-first sample — the two coverage artifacts below let you check that.

- **Artifact 1 — [`entry-points.md`](./entry-points.md):** every external function on
  the token, TaxProcessor, and Dividend, plus the Portal forwarders that reach them,
  each with its guard and a reason (many confirmed by live unprivileged simulation).
- **Artifact 2 — [`state-dependency-map.md`](./state-dependency-map.md):** what writes
  each shared value, who reads it, and the ten single-actor compositions I staged and
  why each dead-ends.

## Scope

The bespoke, CETS-specific logic — the only code that can carry a CETS-specific bug:

- **CETS token** — FlapTaxTokenV3 (clone `0xb0c2…7777` → impl `0x024f…6422`)
- **TaxProcessor** — TaxProcessorUniV2 + TaxProcessorBase family (clone `0xfe03…97D4`
  → impl `0x8863…7d40`; delegatecall bodies `ADMIN_IMPL 0x1271D4…`,
  `DISPATCH_IMPL 0x0B4655…`)
- **Dividend** (clone `0x2576…B3cF` → impl `0xcc11…0d71`)
- **Portal** (`0xe2cE…9De0`) — audited for its *interface to CETS's fund contracts*
  (it owns them), i.e. every forwarder that can sweep/reconfigure the TaxProcessor or
  Dividend. Its full internal launchpad surface is out of scope (see Assumptions).

Excluded as audited-and-genuine (not re-reviewed for bugs): PancakeSwap V2
pair/router/factory, WBNB, the Safe singletons, OpenZeppelin v4.9.4, Solady v0.0.201 —
all byte-identical to upstream (`../integrity/integrity-report.md`), the pair
CREATE2-proven canonical. XAUt is Tether's. The SwapRegistry/MultiDexRouter are dead
code for CETS (`dividendToken == quoteToken`).

## How the system moves money and grants power (the model I attacked)

- **Value backing.** Each CETS is a fixed-supply memecoin; the "gold" is real XAUt
  (Tether Gold) that a 3% buy/sell tax buys on the CETS/XAUt pool and pays to holders.
- **Where value enters/leaves.** Enters as tax skimmed on pool trades (accrues as CETS
  on the token). Leaves when `_liquidateTax` → `TaxProcessor.processTaxTokens` swaps it
  to XAUt (`amountOutMin=0`) and splits it: 10% protocol fee → fee Safe; then of the
  rest 3% market EOA, 10% burned, 5% LP→`0xdead`, 82% → Dividend as XAUt for holders.
  Holders pull XAUt via `withdrawDividends`.
- **Who may do what, and how it's proven.** Holders' shares == their CETS balance,
  written only by the token (`onlyTaxToken setShare`). Fund sweeps and reconfiguration
  are `onlyOwner`, owner = the Portal, whose recover/tweak functions are DEFAULT_ADMIN/
  MANAGE-gated to the launchpad Safe `0x1f96…8A3b` (3-of-4). The token's own owner is
  renounced and its wiring is immutable post-init.
- **What must stay true for honest users not to be robbed** (the properties I targeted):
  (P1) a share earns only dividends deposited while it exists; (P2) accrued value
  reaches only configured receivers or holders; (P3) no one but the owner/roles can
  sweep or repoint the fund contracts; (P4) the token cannot be re-pointed or
  re-parameterised by a non-owner; (P5) no unprivileged caller can mint/inflate a share
  or claim another's funds. Artifact 2 shows each holds.

## What I did NOT find (and specifically checked)

- **No re-initialisation / ownership seizure** — all three clones `_initialized=1`,
  re-init reverts (simulated).
- **No missing/defeatable guard on a fund mover** — every sweep, setter, and mint-share
  path is `onlyOwner`/`onlyTaxToken`/`self`/role, confirmed by unprivileged simulation
  (token, TaxProcessor, Dividend, and all 13 Portal forwarders).
- **No self-grantable privilege, forgeable/replayable signature, or key-in-code** — no
  `ecrecover`/custom signature scheme in the bespoke code (only OZ `permit`, user's own
  sig + nonce); no hardcoded signer key (only infra/price-anchor constants); no
  attacker-controllable `delegatecall` (targets are immutable) or arbitrary external
  `call` (low-level calls go only to configured receivers with empty calldata).
- **No dividend-accounting exploit** — share==balance, `rewardDebt` excludes prior
  deposits, ceilDiv rounds against the claimant, no `mdps` overflow is fundable.
- **No composition extraction** — the JIT-dividend, share-fragmentation, donation/
  reconcile, bonding-curve-tax, unregistered-pool, and reentrancy sequences all
  dead-end (Artifact 2, C1–C10).

## The real risks — present, but excluded by the audit's own rules

Stated so the negative verdict isn't mistaken for "nothing can go wrong":

1. **Privileged drain (dominant).** The launchpad Safe `0x1f96…8A3b`, via the Portal it
   controls (DEFAULT_ADMIN + upgradeable), can call `recoverStuckDividend` /
   `recoverStuckTaxProcessor` → `Dividend.emergencyWithdraw` / `TaxProcessor.withdrawAll`
   and drain the XAUt held for holders, and can redirect future dividends
   (`setReceivers`, `setTaxTokenDividendReceiver`). I **confirmed** this is gated to the
   Safe (unprivileged callers revert; the Safe succeeds in simulation). This is a
   *privileged party using legitimate power* — out of finding scope — but it is the
   thing most likely to actually take holder funds. Detailed in `../UNRESOLVED.md` §A1
   and `../TRUST_GRAPH.md`.
2. **MEV on tax liquidation.** `TaxProcessorUniV2._swapTokensForQuote` and `_addLiquidity`
   use `amountOutMin/amountMin = 0`, so every liquidation is sandwichable; value that
   should become holders' gold leaks to searchers. This is *ordering/sandwich* — out of
   finding scope — but a genuine, ongoing value leak. `../UNRESOLVED.md` §A4.

Neither is a bug an unprivileged actor can exploit through a code flaw; both are the
categories the brief explicitly excludes. I report them as risk, not as findings.

## Assumptions and what would change the verdict

- **Portal internals / `PortalTweak` module.** The Portal's recover/tweak functions
  `delegatecall` into module contracts (e.g. `PortalTweak`) whose source I did not read
  (private immutables, launchpad-internal). I confirmed their **gating** behaviorally —
  unprivileged calls revert with role errors, the DEFAULT_ADMIN Safe succeeds. A single
  simulation cannot rule out an exotic role-bypass hidden in that module. *If* a
  `PortalTweak` path let a non-role caller reach `withdrawAll`/`emergencyWithdraw` on
  CETS's contracts, that would be a critical unauthorized-access finding — I saw no
  evidence of it, but flag the module as read-by-behavior, not by source.
- **XAUt (Tether Gold) is a well-behaved ERC-20.** The deposit/dispatch/withdraw flows
  assume XAUt has no transfer hook / reentrancy / fee-on-transfer surprise. It is the
  genuine Tether OFT (integrity-checked); if Tether shipped an upgrade adding a transfer
  callback, the reentrancy analysis (C8) would need revisiting.
- **Portal `getTokenV8(CETS).status == DEX`.** The TaxProcessor's reconcile/burn
  branches key off this Portal read; flipping it is Portal-privileged (migration), not
  attacker-reachable. If an unprivileged Portal bug could flip a token's status, the
  burn/reconcile branch selection could be influenced (still no direct extraction).
- **SwapRegistry stays inactive.** Conclusions rely on `dividendToken == quoteToken`
  (Case-3 dead). An owner `setDividendToken` to a third token would pull the unverified
  SwapRegistry impl into the value path; re-audit needed then.

## Reproduce

All guard/reachability claims were checked against live BSC state with `eth_call` from
the unprivileged address `0x1111…1111` (no transactions sent). See `../tools/`
(`simulate.py`, `chain.py`) and the Portal-forwarder probes recorded in this audit.
