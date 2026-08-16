# Subsystem audit — oHYDX option / cheap-sell (Hydrex, Base 8453)

Scope contracts (source under `/home/user/cetong/contracts/options/`):
- **OptionTokenV4** `0xa1136031150e50b015b41f1ca6b2e99e49d8cb78` — `OptionTokenV4_0xa113cb78/contracts/OptionToken/OptionTokenV4.sol`
- **OptionFeeDistributor** proxy `0xdb2fc14d…` / impl `0xb677…` — `OptionFeeDistributor_0xb677cc55/contracts/OptionToken/OptionFeeDistributor.sol`
- **SimpleFloorGuardian** proxy `0xa007970f…` / impl `0xeb39…` — `SimpleFloorGuardian_0xeb39998f/contracts/OptionToken/SimpleFloorGuardian.sol`
- **AlgebraIntegralTwap** `0xf524522b…` — `AlgebraIntegralTwap_0xf5246ea7/contracts/OptionToken/DynamicTwapOracle/AlgebraIntegralTwap.sol`

**Bottom line: no findings survived rebuttal.** The subsystem is well protected by (a) a fixed floor price that currently *binds above* the 30% TWAP discount, (b) dimensionally consistent decimal handling (verified against live values), (c) atomic‑manipulation‑resistant Algebra tick TWAP, and (d) the fact that every value‑releasing path requires burning the caller's own oHYDX 1:1, so an attacker's gain is bounded by oHYDX they must acquire at fair market price.

---

## Live state (READ from Base at audit time, block ~latest 2026-08-16)

| Param | Value | Meaning |
|---|---|---|
| `OptionTokenV4.discount()` | 30 | pay 30% of TWAP (70% discount) — *when discount binds* |
| `OptionTokenV4.twapSeconds()` | 7200 | 2h TWAP window |
| `isPaused()` / `permissionedMint()` | false / false | exercise open; **anyone can mint** oHYDX 1:1 |
| `totalSupply()` oHYDX | 31,055,229.23 | == HYDX held by OptionTokenV4 (**1:1 backed**) |
| `UNDERLYING_TOKEN` / `paymentToken` | HYDX (18 dec) / USDC (6 dec) | |
| `feeDistributor.floorPrice()` | 10000 | **0.01 USDC per 1 HYDX** floor |
| TWAP price `estimateAmountOut(HYDX,1e18,7200)` | 15204 (0.015204 USDC) | market ≈ **0.0152 USDC/HYDX** |
| `getDiscountedPrice(1000 HYDX)` | 4,561,239 (4.56 USDC) | 30% of market |
| `getMinPrice(1000 HYDX)` | 10,000,000 (**10.0 USDC**) | **floor binds** (max(floor, discounted)) |
| pool (oracle) = pair | `0x51f0…d3d2` (Algebra), token0=HYDX token1=USDC | 21.55M HYDX / 229.9k USDC depth |
| FD / FG / OT USDC balances | 1 / 0 / 3 wei | no USDC honeypot; the 31.06M HYDX in OT is the only pot |
| ADMIN/MINTER/PAUSER roleAdmin | `ADMIN_ROLE` (self-administered); holder `0x1ae3…0311` | not self-grantable |
| FD/FG `owner()` | `0x1ae3…0311` | proxies already initialized |

**Units are consistent (no decimal bug):** live `getDiscountedPrice(1000)=4.56 USDC` is exactly 30% of the 15.2 USDC market value, and `getMinPrice=10 USDC` is exactly the 0.01 USDC/HYDX floor × 1000. The classic Velocimeter-fork "1e12 units mismatch" is **not present** here.

---

## 1. Entry-point table (all state-changing entry points of the 4 in-scope contracts)

### OptionTokenV4 — 22 state-changing (non-proxy; constructor-init, immutable UNDERLYING)

| Fn (file:line) | Guard | Why safe / exploitable |
|---|---|---|
| `exercise(u,u,addr)` :233 / `exercise(u,u,addr,deadline)` :248 | none (+deadline) | Safe. `_exercise` burns caller's oHYDX first (:545); releases exactly `_amount` HYDX for `max(floor,30%·TWAP)` USDC. Bounded 1:1 by caller's oHYDX. |
| `exerciseVe(u,addr)` :266 | none | Safe. Burns caller oHYDX (:566), locks the same `_amount` HYDX into a **permanent** veNFT for recipient. Releases ≤ what was burned; HYDX is locked, not extracted. |
| `exerciseExternal(opt,u,dl,bytes)` :284 | `isExternalOption[opt]` (admin whitelist) | Reachable only for admin-whitelisted options; whitelist empty. Approval scoped to exactly `_amount` and reset to 0 (:296-299). Attacker can't add an option. Out of scope (privileged). |
| `mint(to,amount)` :511 | `onlyMinter` (perm-mint off ⇒ open) | Safe. Pulls `_amount` HYDX, mints `_amount` oHYDX — exact 1:1, no bonus/rounding gain. |
| `burn(amount)` :455 | `onlyAdmin` | Privileged. Burns caller's own oHYDX, returns 1:1 HYDX — bounded by admin's holdings. |
| `pause` :528 / `unPause` :468 | `onlyPauser` / `onlyAdmin` | Gated to `0x1ae3`. |
| `setDiscount` :430 / `setTwapSeconds` :440 / `setFeeDistributor` :421 / `setPaymentConfiguration` :380 / `toggleExternalOption` :493 / `togglePermissionedMint` :481 | `onlyAdmin` | Gated. Discount∈(0,100], twap∈[1h,2d] validated. |
| `grantRole` / `revokeRole` :(OZ) | `onlyRole(getRoleAdmin)` = ADMIN_ROLE | Not self-grantable (verified live: dead has no role, ADMIN self-administered). |
| `renounceRole` :(OZ) | self only | Renounce own role only. |
| `approve`/`increaseAllowance`/`decreaseAllowance`/`transfer`/`transferFrom` | ERC20 std | Standard oHYDX token accounting; no underlying release. |

Key views (pricing surface): `getMinPrice` :333/:346, `getMinPaymentAmount` :321, `getDiscountedPrice` :353/:361, `getTimeWeightedAveragePrice` :368, `getVotingEscrow` :311 — all pure reads; analyzed in §2/§3.

### OptionFeeDistributor — 7 state-changing

| Fn (file:line) | Guard | Why safe / exploitable |
|---|---|---|
| `distribute(token,payout,amount)` :159 | **none** | Safe despite no guard: every transfer is `safeTransferFrom(msg.sender,…)` (:169,:182) — pulls from the **caller**. An external caller only donates their own tokens; the OptionToken's max approval to FD is only drawn when `msg.sender==OptionToken` (i.e. inside a real exercise). No protocol funds movable. |
| `setFeeReceiver` :103 / `setFloorPrice` :114 / `setFloorGuardian` :126 | `onlyAllowed` (owner or FEE_MANAGER) | Gated to `0x1ae3` / registry role. |
| `initialize` :65 | `initializer` | Already initialized (owner set). |
| `renounceOwnership` / `transferOwnership` | `onlyOwner` | Gated. |

### SimpleFloorGuardian — 5 state-changing

| Fn (file:line) | Guard | Why safe / exploitable |
|---|---|---|
| `deposit(token,amount)` :92 | **none** | Safe: `principalToken.transferFrom(msg.sender, floorReceiver, amount)` — pulls from caller to the fixed floorReceiver. Pure donation; nothing else movable. |
| `setFloorReceiver` :78 | `onlyAllowed` | Gated. |
| `initialize` :46 | `initializer` | Already initialized. |
| `renounceOwnership` / `transferOwnership` | `onlyOwner` | Gated. |

### AlgebraIntegralTwap — 0 state-changing (view-only oracle)

| Fn (file:line) | Guard | Why safe / exploitable |
|---|---|---|
| `estimateAmountOut(tokenIn,amountIn,secondsAgo)` :23 | view | Reads `plugin().getTimepoints([secondsAgo,0])` — pure tick **TWAP**, never spot. Manipulation analysis in §3-B. |
| `pool`/`token0`/`token1` | immutable views | Constant. |

**Entry points accounted for: 34 state-changing (22 + 7 + 5 + 0) across the 4 in-scope contracts, plus the pricing/oracle view surface.** Every one is either (a) an AccessControl/Ownable-gated privileged setter reachable only by `0x1ae3…`, (b) a pull-from-caller function that cannot move protocol funds, or (c) a value-releasing path (`exercise`/`exerciseVe`/`mint`) that requires and is bounded 1:1 by the caller's own oHYDX.

---

## 2. State read/write + composition table (what was tried)

| Composition attempted | Mechanism | Result |
|---|---|---|
| **Flash-loan cheap drain** of the 31M HYDX pot | Any HYDX release requires burning oHYDX (`_burn(msg.sender,·)` first in `_exercise`/`_exerciseVe`). Live `exercise` from `0xdEaD` reverts `burn amount exceeds balance`. | **Fails.** Gain is *not* independent of stake — attacker must own oHYDX (acquired at fair market). Flash loans give no leverage; mint→exercise is 1:1 + you pay the floor = net loss. |
| **TWAP down → cheap `getDiscountedPrice`** then exercise | `getMinPrice = max(floorAmount, 30%·TWAP)`; write B (`_exercise`) reads oracle A (`estimateAmountOut`). | **Fails.** Floor binds now (0.01 > 0.00456). Lowering TWAP to 0 still pays the floor. Even if discount bound (needs HYDX>0.0333), it's capped at floor. See §3-B for manipulability math. |
| **Atomic single-tx TWAP move** (flash-swap the pool, exercise in same tx) | Algebra plugin writes a timepoint at `now` recording the *pre-swap* tick; the current (moved) tick gets elapsed-weight 0 at `secondsAgo=0`. | **Fails.** 2h TWAP is unchanged within the tx. Confirmed live: `est(1,3600)`≈`est(1,60)`≈`est(1,1)` all ≈0.0151 (stable). |
| **Reentrancy** via HYDX/USDC transfer or veNFT mint callback | `_exercise`: burn→pull USDC→`distribute`→`safeTransfer` HYDX. `_exerciseVe`: burn→approve ve→`createLockFor`. | **Fails.** HYDX/USDC are plain ERC20 (no hooks); FD/FG/ve are trusted, no attacker callback. Even if `onERC721Received` fires in `createLockFor`, OptionTokenV4 keeps no reentrancy-sensitive accounting; a reentrant call still needs the caller's oHYDX. |
| **Permissionless `distribute` / `deposit`** to redirect protocol USDC | Missing guard on both. | **Fails.** Both pull from `msg.sender`; the OptionToken's `type(max)` approval to FD is only usable when `msg.sender==OptionToken`. Nothing lets an outsider make FD pull from the OptionToken. |
| **Self-grant privilege / re-init proxies** | `grantRole`, `initialize`. | **Fails.** Roles self-administered by ADMIN_ROLE (dead holds none); FD/FG already initialized (owner `0x1ae3`). |
| **`exerciseVe` free HYDX extraction** | Burn oHYDX → permanent veNFT. | **Fails.** Releases only the `_amount` you burned into a *permanent* (non-withdrawable) lock; cannot exceed burned amount, cannot touch the rest of the 31M pot. Being "free" is by design (permanent lock benefits protocol). |
| **`uint128(_amount)` truncation** in `getTimeWeightedAveragePrice` :369 | Cast could truncate for `_amount>2^128`. | **Fails/unreachable.** Needs `_amount>3.4e38` wei (≫ 3.1e25 total supply); and `floorAmount` uses the *full* `_amount`, so it dominates anyway. |
| **Small-amount rounding to 0 payment** | For `_amount<1e14` wei, both floor and discounted round to 0 → 0 USDC exercise. | **Fails (dust).** oHYDX is 1:1 backed, so burning dust oHYDX for dust HYDX is net-zero value; scaling needs 10^4+ txs/HYDX, gas ≫ value. |

---

## 3. Detailed rebuttals of the two closest calls

### A. Floor price bounds the loss — the decisive protection (READ + arithmetic)

`getMinPrice` (`OptionTokenV4.sol:333-338`):
```solidity
uint256 floorPriceAmount = (getMinPaymentAmount() * _amount) / (10 ** UNDERLYING.decimals());  // 10000·amt/1e18
uint256 discountedAmount = getDiscountedPrice(_amount, _discount);                              // (TWAP·amt)·30/100
return floorPriceAmount > discountedAmount ? floorPriceAmount : discountedAmount;
```
With live `floorPrice=10000` and HYDX≈0.0152 USDC:
- floorAmount = 0.01 USDC/HYDX
- discountedAmount = 0.30 × 0.0152 = 0.00456 USDC/HYDX

`0.01 > 0.00456` ⇒ **floor binds**; every exercise pays **≥ 0.01 USDC/HYDX = ~66% of market**. The floor is a fixed admin scalar (not oracle-derived, not attacker-influenceable), and `distribute` re-checks it (`OptionFeeDistributor.sol:160-161`). Because the floor sits *above* the discount, TWAP has zero influence on price at current levels — an attacker cannot buy HYDX below 0.01 USDC no matter what they do to the oracle.

### B. TWAP manipulability (INFERRED from Algebra/UniV3 oracle mechanics + live confirmation)

`AlgebraIntegralTwap._getTimeWeightedAverageTick` (:36-49) reads `getTimepoints([7200,0])` and divides the tick-cumulative delta by 7200 — a pure 2h time-weighted tick, no spot read. Two independent reasons manipulation is non-viable:

1. **Atomic manipulation is inert.** The Algebra volatility-oracle plugin writes a timepoint at the start of the manipulating swap, recording the tick that prevailed *up to* `now`; the freshly-moved tick therefore carries elapsed-time weight 0 for the `secondsAgo=0` endpoint read in the same block. So a flash-swap-then-exercise in one tx leaves the 2h TWAP unchanged. (Confirmed indirectly: 1s/60s/3600s windows all return ≈0.0151.)
2. **Sustained manipulation is capped and unprofitable.** Moving the 2h average requires holding a displaced price for a large fraction of 7200s against arbitrage (pool depth only 229.9k USDC / 21.55M HYDX → continuous arb bleed), and even a TWAP→0 only reduces the *discounted* leg, which is already below the binding floor. Net benefit at current prices: **0**. The discount leg only becomes relevant if HYDX > floor/0.3 = 0.0333 USDC (>2.1× current), and even then price is floored at 0.01.

`AlgebraIntegralTwap.getQuoteAtTick` (:52-65) omits UniV3's `sqrtRatio > uint128.max` branch, so extreme ticks would make `sqrtRatioX96*sqrtRatioX96` revert (Sol 0.8 overflow) — a *liveness* (fail-safe DoS) edge at absurd prices, never a mispricing/theft. Not a fund-loss finding.

---

## Minor / non-findings noted for defense-in-depth (not exploitable by an unprivileged attacker)

- `exerciseExternal` (:284) lacks the `notPaused` modifier that `_exercise`/`_exerciseVe` have — a paused contract could still release HYDX through a whitelisted external option. Inert today (whitelist empty; adding requires admin). Consider adding `notPaused` for consistency.
- `distribute` / `SimpleFloorGuardian.deposit` are permissionless. Harmless (pull-from-caller) but an explicit `msg.sender == optionToken` guard on `distribute` would be cleaner.
- `OptionFeeDistributor.distribute` hardcodes `10**18` (:160) for the underlying's decimals while `OptionTokenV4.getMinPrice` reads `UNDERLYING.decimals()` dynamically (:334). Consistent only because HYDX is 18-dec; a non-18-dec underlying would desync the floor check. Fine for this deployment.
- For `_amount < 1e14` wei HYDX both price legs round to 0 (dust); floor protection effectively disappears at sub-0.0001-HYDX granularity. Not economically reachable (gas-bound; 1:1 backing means no net extraction).

## Assumptions
- HYDX (`0x0000…6b30`) and USDC (`0x8335…2913`) behave as standard ERC20s (no transfer hooks) — HYDX is the protocol's own plain mint/burn ERC20; USDC is canonical Base USDC. READ: both used via `safeTransfer`/`safeTransferFrom` with no receiver callback.
- VotingEscrowV2 (`0x25b2…`, out of scope) treats `LockType.PERMANENT` as non-withdrawable; even if it did not, `exerciseVe` still only releases the oHYDX the caller burned (1:1), so it cannot drain the pot.
- Admin key `0x1ae3…0311` is honest (privileged setters excluded per scope rules).
