# Artifact 1 — Complete entry-point enumeration

Every externally-reachable function on the CETS-specific bespoke contracts, built
mechanically from source (not by judgment about importance), each with the guard
that protects it and a one-line reason it is not exploitable by an unprivileged
attacker — or a note if it is.

**Scope of this table.** The three clones an attacker actually interacts with — the
CETS token, the TaxProcessor, the Dividend — plus the Portal forwarders that can
reach those two fund contracts. Canonical dependencies (PancakeSwap pair/router/
factory, WBNB, the Safe singletons, OpenZeppelin, Solady) are excluded here: they are
byte-identical to audited upstream (see `integrity/integrity-report.md`) and carry no
CETS-specific logic. XAUt is Tether's. The SwapRegistry / MultiDexRouter are inactive
for CETS (`dividendToken == quoteToken`), noted at the end.

Legend for "reachable" empirical checks: functions marked **[sim]** were executed via
`eth_call` from an arbitrary unprivileged address `0x1111…1111` against live BSC state
(`tools/simulate.py`, and the Portal probes in this session); the observed revert /
success is quoted.

Contract addresses: token `0xb0c2…7777` (impl `0x024f…6422`), TaxProcessor
`0xfe03…97D4` (impl `0x8863…7d40`; delegatecalls admin `0x1271D4…`, dispatch
`0x0B4655…`), Dividend `0x2576…B3cF` (impl `0xcc11…0d71`), Portal `0xe2cE…9De0`.

---

## 1. CETS token — FlapTaxTokenV3 (clone `0xb0c2…7777`)

Custom functions:

| Function | Guard | Why not exploitable |
|---|---|---|
| `initialize(InitParams)` | `initializer` | Already initialized (`_initialized=1`); re-call reverts "already initialized". **[sim-analogue: Dividend re-init reverts]** |
| `startMigration()` | `onlyOwner` | Owner renounced (`owner()==0x0`) → permanently uncallable. **[sim] reverts "Ownable: caller is not the owner"** |
| `finalizeMigration()` | `onlyOwner` | Same — dead. **[sim] reverts** |
| `state()/taxRate()/buyTaxRate()/sellTaxRate()/liquidationThreshold()/taxExpirationTime()/antiFarmerExpirationTime()/getPoolStateData()` | view | Read-only. |

Inherited ERC20 / ERC20Permit / Ownable surface (OZ v4.9.4, byte-identical to upstream):

| Function | Guard | Why not exploitable |
|---|---|---|
| `transfer/transferFrom` | allowance / balance | Triggers `_liquidateTax(to)` + tax + `setShare`. Moves only the caller's own tokens; tax accrues to the token and is liquidated to holders. No path to others' funds. Composition analysis in Artifact 2. |
| `approve/increaseAllowance/decreaseAllowance` | — | Standard allowance bookkeeping. |
| `permit(owner,spender,value,deadline,v,r,s)` | EIP-2612 sig + nonce + deadline | Genuine OZ ERC20Permit; per-owner nonce prevents replay, requires the owner's own signature. |
| `owner()/name()/symbol()/decimals()/totalSupply()/balanceOf/allowance/nonces/DOMAIN_SEPARATOR` | view | Read-only. |
| Ownable `transferOwnership/renounceOwnership` | `onlyOwner` | Owner is `0x0` → uncallable. |

No public `mint`/`burn` exists. Supply is fixed at 1e9 minted once to the deployer
(Portal) in `initialize`; deflation "burns" are ordinary transfers to `0xdead`
performed by the TaxProcessor. Token wiring (`taxProcessor`, `dividendContract`,
`pools`, `quoteToken`, `mainPool`, `v2Router`) is set once in `initialize` and has no
setter — **immutable post-init**, so an attacker cannot re-point the token at a
malicious processor/dividend.

## 2. Dividend (clone `0x2576…B3cF`)

| Function | Guard | Why not exploitable |
|---|---|---|
| `initialize(address,address,uint256)` | `initializer` | Already initialized. **[sim] reverts "Initializable: contract is already initialized"** |
| `setShare(user,share)` | `onlyTaxToken` | Only the CETS token can call; it always passes `balanceOf(user)`, so share == real balance and cannot be inflated. **[sim] reverts "Dividend: caller is not the tax token"** |
| `deposit(amount)` | permissionless | Pulls `dividendToken` (XAUt) **from msg.sender** and raises `magnifiedDividendPerShare`. Depositor gives value to shareholders; cannot profit. |
| `distributeDividend(users[])` | permissionless | Pushes each listed user **their own** owed dividends **to that user**. Cannot redirect to caller. |
| `withdrawDividends()` | permissionless | Claims **caller's own** dividends. **[sim] reachable, returns 0 for a non-holder** |
| `withdrawDividendsFor(user)` / `withdrawDividendsFor(user,bool)` | permissionless | Sends **user's own** dividends to `user` (not to caller). CEI: state updated before transfer; XAUt `safeTransfer`, no reentrancy. |
| `withdrawableDividends/withdrawableDividendOf/accumulativeDividendOf/getMagnifiedDividendPerShare/userInfo/totalShares/…` | view | Read-only. |
| `excludeAddress/unexcludeAddress` | `onlyOwner` | Owner = Portal. **[sim] reverts "Ownable: caller is not the owner"** |
| `setDividendToken(newToken)` | `onlyOwner` + `require(mdps==0)` | Owner-only **and** locked forever once any dividend has been distributed (`mdps>0` now) → cannot switch the payout token. |
| `setMinimumShareBalance(x)` | `onlyOwner` | Owner = Portal. |
| `emergencyWithdraw(token,amount,to)` | `onlyOwner` | **The sweep.** Owner = Portal (privileged). **[sim] reverts "Ownable: caller is not the owner"** — see §5 for the privileged path. |
| `receive()` | — | Accepts ETH (for WETH-unwrap path, unused since dividendToken=XAUt). |

## 3. TaxProcessor — TaxProcessorUniV2 / …Core (clone `0xfe03…97D4`)

The clone runs `TaxProcessorCore`; admin/dispatch bodies run by `delegatecall` into
`ADMIN_IMPL`/`DISPATCH_IMPL` in the clone's storage, so the modifiers below execute
against the clone's owner/taxToken.

Value-moving / state-changing:

| Function | Guard | Why not exploitable |
|---|---|---|
| `processTaxTokens(taxAmount)` | `onlyTaxToken` | Only the CETS token calls it (during liquidation). **[sim] reverts "TaxProcessor: caller is not the tax token"** |
| `dispatch()` | `nonReentrant`, permissionless | Distributes accrued buckets to the **configured** receivers (feeReceiver Safe, market EOA, Dividend) and reconciles surplus into the same buckets. Cannot redirect a cent to the caller. **[sim] reachable, no-op-safe.** Compositions in Artifact 2. |
| `processBondingCurveTax(quoteAmount)` | permissionless | Pulls `quoteToken` (XAUt) **from msg.sender** then books it into distribution buckets. Caller donates. **[sim] reverts "ERC20: transfer amount exceeds balance"** from an unfunded caller. |
| `reconcileToken(tokenAmount)` | `require(msg.sender==address(this))` | Self-call only (from `_afterReconcile`). External callers rejected. |
| `initialize(TaxProcessorV2InitParams)` | `initializer` (via ADMIN_IMPL) | Already initialized. |
| `withdrawAll(token,to)` | `onlyOwner` (ADMIN_IMPL) | **The sweep.** Owner = Portal (privileged). **[sim] reverts "Ownable: caller is not the owner"** — see §5. |
| `setReceivers/setTaxConfig/setWalletConfig/setFeeRate/setMinBuyBackQuote/setMaxBuyBackGasLimit/setCommissionConfig/setDividendToken/setConverter/setLiqExpectedOutputAmount/setLiqSmoothingGapQuote/setAutoForwarding/setDispatchThreshold/setDispatchCheckCooldown` | `onlyOwner` | Owner = Portal (privileged). **[sim] setConverter/setReceivers revert "Ownable: caller is not the owner"** |
| `registerV4LPFeeSource(...)` | `onlyPortal` | Also overridden in UniV2 to `revert("V4 fee source unsupported")` — doubly dead. |
| `checkAndNotifyDispatch()` | — (UniV2 override) | No-op `{}` for V2 tokens. |
| `executeDispatch()` (on DISPATCH_IMPL directly) | — | Runs in the **empty** storage of the stateless impl contract; no funds there. Harmless. |

Views: `getQuoteToken/marketAddress/requiresMEVProtection/feeConfig/feeConfigV2/
feeConfigV3/commissionBps/getWalletConfig/totalQuoteSentToDividend/dividendQuoteBalance/
feeQuoteBalance/lpQuoteBalance/marketQuoteBalance/pendingDividendQuoteTokenBalance/
dividendTokenBalance/commissionQuoteBalance/totalDividendTokenSent/…` — read-only.

`receive()` — for CETS `isWeth=false` and `autoForward=false`, so it accepts ETH and
returns without forwarding. No value path.

## 4. Portal forwarders that can reach CETS's fund contracts (`0xe2cE…9De0`)

The Portal **owns** the TaxProcessor and Dividend, so its recover/reconfigure
functions are the one place a bug could turn the privileged sweep into an open door.
Each was executed from the unprivileged address **[sim]**; all are gated.

| Function | Observed guard **[sim from 0x1111…]** |
|---|---|
| `recoverStuckTaxProcessor(taxProcessor,token,to)` | reverts `AccessControl … missing role 0x00…00` (DEFAULT_ADMIN) |
| `recoverStuckTaxProcessorToTaxToken(taxProcessor,token)` | reverts `AccessControl … missing role 0x59a1c4…` |
| `recoverStuckDividend([(taxToken,amount,to)])` | reverts `Error("Caller is not admin")`; **succeeds only from the launchpad Safe** (DEFAULT_ADMIN) |
| `recoverStuckTaxToken(taxToken)` | reverts custom `0x50f69a4e` (manage-role check) |
| `burnStuckTaxToken(taxToken)` | reverts `AccessControl … missing role 0x00…00` |
| `excludeAddressFromDividends(taxToken,account)` | reverts `0x50f69a4e` |
| `changeMarketWallet(token,newWallet)` | reverts `0x50f69a4e` |
| `setTokenDividendToken(taxToken,newDividendToken)` | reverts `0x50f69a4e` |
| `setTaxTokenDeferredOrigin(taxToken,origin,bool)` | reverts `0x50f69a4e` |
| `setTaxTokenDividendKeeper(taxToken,keeper,bool)` | reverts `0x50f69a4e` |
| `setTaxTokenDividendReceiver(taxToken,holder,receiver)` | reverts `0x50f69a4e` |
| `retuneTaxThresholds(taxToken)` | reverts `0x50f69a4e` |
| `inspect(bytes)` | selector-whitelisted to view-only lens calls; any other selector → `revert FeatureDisabled()`; cannot reach `withdrawAll`/`emergencyWithdraw` |
| `sendMsg(token,message)` | emits an event only; touches no funds |
| `setBitFlags/halt/setNewFeatureSwitch/auditorRunIdempotent/…` | role-gated (DEFAULT_ADMIN / GUARDIAN / AUDITOR / MANAGE); do not move CETS funds |

**Conclusion for §4:** every Portal path that can sweep or reconfigure CETS's fund
contracts is gated to a role held by the launchpad Safe. No unprivileged reach.
(The gate lives in the delegatecalled `PortalTweak` module; its enforcement is
confirmed behaviorally from both an unprivileged address (revert) and the Safe
(success) — see Assumptions in `audit/README.md`.)

## 5. The owner path (privileged — out of finding scope, stated for completeness)

`Dividend.emergencyWithdraw` and `TaxProcessor.withdrawAll` are `onlyOwner`; the owner
is the Portal; the Portal's `recoverStuckDividend`/`recoverStuckTaxProcessor` are
DEFAULT_ADMIN-gated to the launchpad Safe `0x1f96…8A3b` (3-of-4). So the Safe can
drain the XAUt held for holders and redirect future flows. This is a **privileged
party using its legitimate power** and is therefore excluded from findings by the
audit rules — but it is the dominant real risk and is documented in
`../UNRESOLVED.md` and `../TRUST_GRAPH.md`.

## 6. Inactive-for-CETS surface (named, not reachable in this config)

- **SwapRegistry** (`0x644A…BEB6`, unverified impl) and **MultiDexRouter**
  (`0xDedF…99ec`): the TaxProcessor touches these only when
  `dividendToken != quoteToken` (Case 3). For CETS both are XAUt, `converter=0`,
  `requiresMEVProtection()=false`, so the registry/converter swap path is dead code
  for this token. Behavior recovered in `../recovered-behavior/SwapRegistry.md`.
