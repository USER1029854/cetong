# Artifact 2 — State-dependency map and composition analysis

Enumerating entry points is the inventory. The exploit, if any, lives in the
composition: one function writes state another reads and trusts. This maps the writes
and reads across the CETS token / TaxProcessor / Dividend, then works the pairs and
sequences an attacker can stage — and shows why each dead-ends.

## Part A — what writes each piece of shared state, and who reads it

| State (contract) | Written by | Read (trusted) by | Attacker can move the writer? |
|---|---|---|---|
| `balanceOf(token)` — accrued tax (token) | every taxed transfer (`_taxedTransfer`) | `_liquidateTax` (compares to `liquidationThreshold`) | Yes — by trading; but see C1 |
| `poolState` {state, buy/sellTax, notLiquidating, threshold, expirations} (token) | `_liquidateTax`, `_processTax`→`_adjustLiquidationThreshold`, time-based transitions, `initialize`/`*Migration` (owner, dead) | `_transfer`, `_getTax`, `_liquidateTax` | Only `notLiquidating`/`threshold` indirectly via triggering a liquidation; time transitions are not movable |
| `pools[addr]` (token) | `initialize` only | `_getTax`, `_afterTokenTransfer` skip-list | No (no setter; owner dead) |
| `userInfo[u]` {share,rewardDebt,pendingBalance}, `totalShares` (Dividend) | `setShare` (onlyTaxToken, = balanceOf), `_setShare`, `_withdrawDividendOfUser` | `deposit`, `withdrawableDividendOf`, `_setShare`, `_withdrawDividendOfUser` | Only the attacker's **own** share, by moving their **own** CETS |
| `magnifiedDividendPerShare` (Dividend) | `deposit` (`+= received*2^128/totalShares`) | `withdrawableDividendOf`, `_setShare`, `_withdrawDividendOfUser` | Yes — anyone can `deposit`, but must supply the XAUt |
| `feeQuoteBalance / marketQuoteBalance / pendingDividendQuoteTokenBalance / lpQuoteBalance / preBondBurnFunds / commissionQuoteBalance` (TaxProcessor) | `_processFeeToken`, `_processFeeQuote`, `_processTokenDistribution`, dispatch clears | `dispatch` (distributes), `_reconcileBalance` (`tracked` sum) | Indirectly — by donating tokens (raises `actual` vs `tracked`) or by causing tax |
| `deferredTaxTokenBalance` (TaxProcessor) | `processTaxTokens` (park while `_swapping`), UniV2 smoothing body | UniV2 smoothing body, `_afterReconcile` (`expected`) | Only via the onlyTaxToken flow (attacker can't call it directly) |
| `quoteToken.balanceOf(TaxProcessor)` — actual (TaxProcessor) | anyone sending XAUt; internal swaps | `_reconcileBalance` (`actual`) | Yes — by donating XAUt (see C4) |
| pool reserves (PancakePair) | any swap/mint/burn/sync | `_quoteToTaxTokens`→`getAmountsIn`, the tax-liquidation swap, `_addLiquidity` | Yes — by trading/flash-loan (see C3) |
| owner / roles (all) | `initialize`; Portal AccessControl | every `onlyOwner`/role gate | No — verified gated (Artifact 1 §4–5) |

The only reads an attacker can influence are: (i) their own `share`, (ii) `mdps` via
a self-funded `deposit`, (iii) the TaxProcessor's `actual` XAUt balance via donation,
(iv) the pool reserves via trading/flash loans. Everything else is written only by
privileged or self-guarded paths. The compositions below work exactly those four.

## Part B — compositions worked

### C1. Buy CETS → trigger tax liquidation → harvest dividend (the JIT-dividend attack)
**Sequence.** Attacker buys a large CETS position (share ← balance via `setShare`),
causes/awaits a liquidation that fills `pendingDividendQuoteTokenBalance`, calls
`dispatch()` to push it into `Dividend.deposit` (raising `mdps`), then
`withdrawDividends()` and sells.
**Why it dead-ends.** The dividend a holder can claim from a deposit `D` is
`share/totalShares · D`. To capture a meaningful fraction the attacker must hold a
meaningful fraction of the **930.7M-CETS** `totalShares`; the pool holds only ~18.4M
CETS and every taxed buy pays 3% + slippage on a ~$160k-XAUt pool. The deposit `D`
itself is only the dividend slice (82%) of 3%-tax already collected — it is bounded by
trading the attacker would have to generate (and pay tax on) themselves. New shares do
**not** earn past deposits: `setShare` sets `rewardDebt = ceilDiv(share·mdps,2^128)` at
the *current* `mdps`, so a freshly-bought position's claimable on prior deposits is 0
(verified in code, `_setShare`). Net result scales with — and is dominated by — the
attacker's own capital and tax cost. Fails the disproportionate-gain bar; excluded.

### C2. Fragment/reassemble shares around a deposit
**Sequence.** Split holdings below `minimumShareBalance` (10,000 CETS) so `setShare`
zeroes them (dropping `totalShares`) right before a `deposit`, then reassemble to
"back-date" a larger share of a smaller-divided `mdps` jump.
**Why it dead-ends.** Reassembling calls `setShare` which resets `rewardDebt` to the
*new, higher* `mdps` — the reassembled position's claimable on the just-happened
deposit is ~0. The attacker only succeeds in **excluding themselves** from the deposit
(everyone else earns more). Self-harming. No extraction.

### C3. Flash-distort pool reserves → drive the smoothing math / liquidation swap
**Sequence.** Flash-loan-swap to move the CETS/XAUt reserves, so
`_quoteToTaxTokens`→`getAmountsIn` returns a manipulated `gapInTokens`, changing how
much tax is processed vs returned to the token, and making the `amountOutMin=0`
liquidation swap execute at a distorted price.
**Why it dead-ends.** The manipulated tokens never reach the attacker — processed tax
becomes XAUt that flows to holders/fee/market; unprocessed tax is returned to the
token or deferred. The only way to convert the distortion into profit is to be the
counterparty to the `amountOutMin=0` swap (buy the dip you created, sell the pop) —
i.e. a **sandwich**, which requires ordering the attacker's own trades around the
victim liquidation. Excluded by the audit rules (front-running / sandwiching). Also
noted: if `getAmountsIn` reverts under manipulation, the code falls back to legacy full
processing (`gapInTokens==0` → `super._processTaxTokensBody`), so there is no revert-DoS
lever either. (The `amountOutMin=0` weakness is real and documented in
`../UNRESOLVED.md` §A4, but it is an MEV weakness, not an unprivileged code-flaw
extraction.)

### C4. Donate XAUt to the TaxProcessor → dispatch reconciles it
**Sequence.** Send XAUt directly to the TaxProcessor so `actual > tracked`, then call
`dispatch()`; `_reconcileBalance` routes the surplus through `_processFeeQuote` into
the fee/market/dividend/lp/burn buckets.
**Why it dead-ends.** The donated surplus is distributed to the **configured**
receivers (and a proportional slice of the dividend bucket goes to *all* holders,
including at most the attacker's small share). The attacker funded 100% and recovers
`< share/totalShares · 82%`. Pure loss. The reconcile has no path that returns value
to the donor.

### C5. Donate CETS to the TaxProcessor → afterReconcile self-processes it
**Sequence.** Send CETS to the TaxProcessor; on the next `dispatch()`,
`_afterReconcile` sees `actual > expected` and self-calls `reconcileToken(stranded)`,
which swaps the CETS to XAUt and distributes.
**Why it dead-ends.** Same shape as C4 — donated CETS is liquidated to holders/fee.
Donor loses. The self-call is guarded (`msg.sender==address(this)`) and re-entrancy of
the nested tax hook is parked by `_swapping` (see C8).

### C6. `processBondingCurveTax` on a DEX-phase token
**Sequence.** Call `processBondingCurveTax(x)` to inject XAUt into the buckets /
`preBondBurnFunds`, then `dispatch()` to trigger a Portal buy-back-and-burn.
**Why it dead-ends.** The function `transferFrom`s the XAUt **from the caller**; the
buy-back burns CETS (to `0xdead`) or refunds to `preBondBurnFunds`. The caller parts
with value and receives nothing. If it pumps CETS the caller holds, that is just an
expensive market buy (minus fees), scaling with the caller's spend. No disproportion.

### C7. Earn dividends through an unregistered pool, extract via LP
**Sequence.** Deploy a second CETS pool not in the token's `pools` set; because
`_afterTokenTransfer` only skips `setShare` for registered pools, the attacker's pool
accrues `share = its CETS balance` and earns dividends; call
`withdrawDividendsFor(attackerPool)` to move XAUt into the pool, then burn LP to take
it.
**Why it dead-ends.** The pool earns the **same** `share/totalShares` dividends the
attacker would earn holding that CETS in a wallet — no amplification. The XAUt lands in
the attacker's own pool and is withdrawn via their own LP: identical economics to a
direct claim, still bounded by their CETS holding and its acquisition cost. (Side
effect: trades on the unregistered pool avoid the 3% tax — fee *avoidance*, which
reduces new dividends but takes nothing from existing holders. Noted as a design
limitation, not a theft.)

### C8. Reentrancy across dispatch → reconcileToken → swap → token hook
**Sequence.** `dispatch()` (nonReentrant) → `_reconcileBalance` → `_afterReconcile` →
external self-call `reconcileToken` → `_processFeeToken` → `_swapTokensForQuote` (sets
`_swapping=true`, sells CETS to the pair) → the token's `_transfer(TaxProcessor→pair)`
fires `_liquidateTax(pair)` → could re-enter `processTaxTokens`.
**Why it dead-ends.** Two independent guards: (a) the token's `notLiquidating` is
`true` here (no token-side liquidation is in flight — dispatch is not a token
transfer), but even a nested `processTaxTokens` is caught by (b) the processor's
`_swapping==true`, which **parks** the nested amount in `deferredTaxTokenBalance` and
returns, instead of processing reentrantly. `dispatch`'s `nonReentrant` additionally
blocks re-entry to `dispatch`/`process... ` guarded functions. No double-spend of any
balance; the parked tokens are accounted and processed later. Dividend payouts follow
checks-effects-interactions (`rewardDebt`/`pendingBalance` cleared before transfer) and
use XAUt `safeTransfer` (no attacker callback), so no reentrancy there either.

### C9. Re-initialize a clone to seize ownership
**Sequence.** Call `initialize` on the token / TaxProcessor / Dividend clone to set the
attacker as owner, then sweep.
**Why it dead-ends.** All three clones have `_initialized==1` (read from storage slot 0)
and reject re-init. **[sim] `Dividend.initialize(...)` → "Initializable: contract is
already initialized".** The implementation contracts themselves ran `_disableInitializers`
in their constructors, so they cannot be initialized either; they also hold no funds.

### C10. Spike `mdps` to overflow `share·mdps` and brick transfers (griefing DoS)
**Sequence.** Deposit a huge amount of XAUt to inflate `mdps` until `setShare`'s
`newShare·mdps` overflows uint256 and reverts, and since `_afterTokenTransfer` reverts
the whole transfer on a `setShare` failure, freeze all CETS transfers.
**Why it dead-ends.** `mdps += received·2^128/totalShares`; `totalShares ≥ 10,000e18`
whenever nonzero (the minimum share), and XAUt total supply is only ~13,148 units·10^6.
Even depositing the entire XAUt supply raises `mdps` by ~4.4e26; `newShare·mdps` with
`newShare ≤ 1e27` stays far below 2^256 (≈1.16e77) — reaching overflow needs ~10^23
full-supply deposits. Not physically fundable. No DoS.

## Part C — barriers that make the above safe (single-actor reachability)

- **Share == balance, always.** `setShare(user, balanceOf(user))` on both sides of
  every transfer means a position cannot be inflated, retained after selling, or
  "flash-held" — reassembly resets `rewardDebt` to current `mdps`.
- **New shares never earn past deposits** (`rewardDebt` set at current `mdps`).
- **Accrued value only ever flows to configured receivers** (feeReceiver Safe, market
  EOA, Dividend→holders) or is burned; no dispatch/reconcile branch pays the caller.
- **Every sweep/reconfigure is `onlyOwner`/role-gated to the Portal→Safe** (Artifact 1
  §4–5, empirically probed).
- **Token wiring is immutable post-init and owner is renounced** — no re-pointing to a
  malicious processor/dividend, no re-init, no live tax-parameter lever.

## Verdict

Working the full write/read map and every single-actor sequence that touches the four
attacker-influenceable reads (own share, self-funded `mdps`, donated balance, pool
reserves), **no composition yields a disproportionate economic gain or an unauthorized
reach to funds/control.** The paths that move real value are either owner/role-gated
(privileged — excluded) or ordering-dependent (MEV/sandwich — excluded). See
`README.md` for the consolidated verdict and assumptions.
