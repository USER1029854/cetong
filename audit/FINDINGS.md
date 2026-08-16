# Hydrex (HYDX) — exploitability findings

Scope: the bespoke Hydrex contracts in this repo (target token + mint/emissions, ve(3,3) core, oHYDX
options, incentives/bribe/classic-pair, Voter + delegatecall logic + registries). Adversary model: a
hostile, **unprivileged**, well-resourced attacker — flash loans, many addresses, atomic multi-step and
cross-transaction sequences, standards-compliant-but-hostile tokens, extreme inputs, unlimited patience.
Method: mechanical enumeration of all **284** state-changing entry points ([`ENTRY_POINTS_raw.md`](./ENTRY_POINTS_raw.md)),
per-entry-point guard analysis, and a state-dependency/composition pass ([`STATE_DEPENDENCY_MAP.md`](./STATE_DEPENDENCY_MAP.md)),
detailed per subsystem in [`subsystem-options.md`](./subsystem-options.md), [`subsystem-ve.md`](./subsystem-ve.md),
[`subsystem-voter.md`](./subsystem-voter.md), [`subsystem-mint.md`](./subsystem-mint.md),
[`subsystem-incentives.md`](./subsystem-incentives.md), plus [`unassigned-contracts-guards.md`](./unassigned-contracts-guards.md).
Excluded per instructions: front-running/ordering/sandwiching, exploits needing other users to trade
mid-attack, and privileged parties misusing legitimate powers (flagged separately below, not counted as findings).

## Verdict

**No economic exploit and no missing/defeatable-guard path to funds or control survived rebuttal for an
unprivileged attacker.** Every value flow that an unprivileged actor can influence is proportional to a
stake they must actually hold (ve weight, oHYDX held, capital swapped), and the accounting that could
break that proportionality — the ve balance/vote/supply checkpoints, the bribe/rebase epoch math, the
Solidly `_k` invariant, the oHYDX floor+TWAP pricing — was worked and holds. The delegatecall modules
(Voter and VotingEscrow) are storage-aligned and immutable-in-layout. This is a genuine "nothing
exploitable" result, not an unfinished one: the full entry-point surface and the cross-function
compositions were both exhausted (see the two artifacts).

What remains is **one real but impact-bounded missing guard**, two **correctness/robustness** defects with
no attacker profit, a set of **privileged/centralization** issues (out of the unprivileged bar but material
to the trust model), and hardening notes. None meets the economic bar; none reaches funds or control.

---

## F-1 · Missing access control on `createGaugeV2` — LOW (unauthorized action, no funds/control reached)

- **Code:** `contracts/liquidity/GaugeFactoryIncentiveCampaign_0x30d5983e/…/GaugeFactoryIncentiveCampaign.sol:69` — `function createGaugeV2(...) external` has **no access modifier** (contrast the intended `onlyAllowed`).
- **Confirmed reachable:** simulated `createGaugeV2(…, token=HYDX, distribution=Voter, …)` from `0x…dEaD` → **SUCCESS**, returns a freshly deployed gauge `0xc88f4753…`.
- **What it breaks / what it does NOT:** any address can deploy `GaugeIncentiveCampaign` BeaconProxies into the factory's `__gauges` array. But these orphan gauges are **never registered in the Voter** (the Voter records the gauge from its own `createGauge` return value, not `last_gauge`), are owned by the factory, and hold no funds — so **no emissions or fees can be diverted and no value or privilege is reached.** The only concrete impact is (a) unbounded `__gauges` growth that can gas-DoS the admin batch `setPermissionsRegistryForGauges()`, and (b) event/state spam.
- **Why it still qualifies (barely):** it is a fund-/config-adjacent function that "should have been closed." Severity is LOW because it reaches neither funds nor control.
- **Cost to attacker:** gas only. **Gain:** none (griefing).
- **Minimal fix:** add the factory's `onlyAllowed`/`onlyGaugeAdmin` modifier to `createGaugeV2` (as the other factory mutators have).

---

## Correctness / robustness defects (no attacker profit — reported for completeness)

### C-1 · `RewardsDistributorV2._claim` strands rebase on an interior zero-balance week — LOW
- **Code:** `contracts/ve-core/RewardsDistributorV2_0x6fcaed42/…/RewardsDistributorV2.sol:172` — `if (balance_of == 0) { continue; }` inside the week loop **without** advancing `week_cursor += WEEK`. The view twin `_claimable` (`:215`) correctly `break`s; canonical Curve/Solidly `ve_dist` always increments the cursor.
- **Effect:** a lock that has an interior week with zero `balanceOfNFTAt` (e.g. expire-then-reactivate, or a gap created by lock mechanics) makes `claim` spin on that week; after `MAX 50` iterations it returns having advanced nothing, permanently **stranding all later-week rebase for that tokenId**. Every division floors down, so it can only under-pay — never over-pay or touch other lockers.
- **Reachability:** self-inflicted; an attacker **cannot** induce it on a healthy third-party lock. No theft, no DoS of others. Below the economic/unauthorized-access bar; listed as a correctness bug.
- **Fix:** `week_cursor += WEEK; continue;` (match `_claimable`).

### C-2 · `claim`/`claimInto`/`claimManyInto` lack caller authorization — INFO (griefing only)
- **Code:** `RewardsDistributorV2.sol:315,330` — no `msg.sender` check. **Not theft:** `_distributeRewards` (`:358`) always routes the rebase to `ve.ownerOf(_tokenId)` via `increaseAmount`/`createLockFor(tokenOwner)` (verified live: `claim(1)` from `0x…dEaD` credits the owner `0xd9e9…`, not the caller). Only effect: a griefer can force a locker's rebase into a fresh **permanent** (non-withdrawable) lock instead of their existing lock. Protocol intent is rebase→permanent-lock anyway. No gain to attacker.

### C-3 · Robustness/hardening notes (not exploitable)
- **BribeV2 `_earnedTokenId` has no `weight ≤ 1e18` cap** (`BribeV2_0x6225a28d/…/BribeV2.sol:231-237`). BribeV2 is the sink for 100% of the main pool's swap fees; its value-conservation relies on the VotingEscrow invariant `Σ_{nft→D} balanceOfNFTAt(nft,T) == getPastVotes(D,T)`. **That invariant was independently confirmed** in `subsystem-ve.md` (delegation is a single-valued atomic move) and `subsystem-voter.md` (all reads are strictly-past snapshots). So conservation holds today; the missing cap is defense-in-depth against a future ve change. Cheap fix: cap the per-NFT weight at `1e18`.
- **Voter vault-type gauges skip DEX-factory validation** (only a whitelisted `asset()` gate). No stake-independent gain (emissions still require votes); robustness note.
- **oHYDX `exerciseExternal` lacks the `notPaused` modifier** (`OptionTokenV4.sol:284`). Inert today — the external-option whitelist is admin-gated and empty — but it should mirror `_exercise`'s pause gate.
- **`OptionFeeDistributor.distribute` hardcodes `10**18`** for the underlying's decimals while `OptionTokenV4.getMinPrice` reads `decimals()` dynamically. Consistent only because HYDX is 18-dec; a latent mismatch if ever reused for a non-18-dec underlying.
- **`ve.supply()` over-counts PERMANENT locks** (`_updateLock`: `supply += V` but credits `V/1.3` power; live `supply()=598.6M` vs actual held `15.12M`). It feeds `Minter.calculate_rebase(_ve.supply(),…)`, inflating the rebase share toward the schedule's rate cap. The extra rebase is still split among lockers by amount-based power (stake-proportional), so no disproportionate capture — a tokenomics quirk, not a finding.

---

## Privileged / centralization issues (out of the unprivileged-attacker bar — flagged for the trust model)

These require a privileged key and so are **not** findings under the stated scope, but they materially bound
how much users must trust the operators (see [`../live-state/AUTHORITIES.md`](../live-state/AUTHORITIES.md)):

- **`MinterV4._initialize` is re-callable by the `governor`** — the re-init guard is `require(_initializer != address(0))` (`MinterUpgradeableV4.sol:272`) but the sentinel written after init is `address(1)` (`:47,:294`), which is `!= address(0)`, so it **never re-arms**. The governor (the 24h Timelock) can re-call `_initialize` and `protocolToken.mint(this, max)` an **arbitrary amount instantly**, bypassing the weekly schedule. Marginal over the governor's existing `setEmissionSchedule` power, but a direct unbounded-mint path. **Fix:** set the sentinel so the guard blocks re-entry (`require(_initializer != _INITIALIZED_ADDRESS)`), or delete the flag post-genesis.
- **`RewardsDistributorV2.withdrawERC20`** (`:401`) lets `owner` (Admin Safe) sweep the distributor's ~799K HYDX.
- **Whole-system control reduces to small key sets** — the mint authority (ProxyAdmin=Timelock can upgrade the Minter), the oHYDX `ADMIN_ROLE` (2-of-4 Admin Safe can retune discount/oracle/floor), and the DEX pool rules/plugin-logic (a single **EOA** `0x74266f2b` + a single 7702 key `0xdead1f5a`). Detailed in `AUTHORITIES.md` / `../live-state/liquidity-analysis.md`.
- **Fee-distributor PermissionsRegistry `0x4180…` still ships the historically-buggy `removeRole`** (swap-and-pop regressions), but it is `onlyAdminMultisig`, never writes the `hasRole` mapping, and is **not** the Voter's registry (`0x3ea4…`, the fixed one). No unprivileged escalation.
- **MevX executor `0x9e9046` has permissionless `executeRoute`/`receiveFlashLoan`** that operate on the contract's own balances (see [`../recovered/`](../recovered/)). Safe **only because it is fund-less by design** (holds 0). Not an unprivileged theft today; becomes one if any token/approval ever rests on it. Hardening: guard the entrypoints or never leave balances/approvals on it.

---

## Compositions worked and rejected (evidence the pairs were examined, not skipped)

| Composition | Why it yields nothing |
|---|---|
| Flash-loan pool → cheap oHYDX exercise | Price = `max(floor, 30%·TWAP_2h)`; floor (0.01 USDC/HYDX ≈ market) binds and is flash-independent; and the plugin writes the timepoint at `now`, so an atomic tick move has **zero** elapsed-weight the same block (verified: 1/60/3600/7200s windows all ≈ unchanged). |
| Inflate ve balance at rebase checkpoint → over-claim | Reward = `balanceOfNFTAt/getPastTotalSupply` over weeks actually held (immutable past reads); paid to the NFT **owner**, not the caller; share scales with locked capital. |
| Vote at epoch boundary → claim full epoch of bribes for briefly-held weight | BribeV2/Voter read strictly-past snapshots keyed by immutable epoch timestamps; per-tokenId `tokenTimestamp` anti-replay; re-vote resets first; weights sum ≤ 1e18. |
| Corrupt Voter/ve storage via delegatecall modules | `VoterV5_Storage` byte-identical across Voter/GaugeLogic/ClaimLogic and sits at slot 0 before the `__gap`; ve LockLogic/ApprovalLogic share the impl's layout and have no layout-changing setter. Provably aligned. |
| Solidly `Pair` free extraction (swap/skim/sync/claimFees/donation) | Fee moved to PairFees before the `_k` check; reserves set to post-fee balances; `lock` blocks reentrancy; new LPs set to current fee index; pair holds no accrued fees to skim. |
| oHYDX `exerciseVe` for "free" | Burns oHYDX (1:1 HYDX-backed) for an equal permanent ve-lock — a fair 1:1 conversion, no free value. |
| Redirect-claim / claim someone else's position | Every claim path pays `ownerOf`/approved recipient; address-keyed paths read only the caller's own balances. |
| Permissionless `distribute`/`notifyRewardAmount`/`deposit` | All pull from `msg.sender` (`safeTransferFrom(msg.sender,…)`); donations shared pro-rata, never profitable; the OptionToken's max-approval to the fee distributor is drawable only when `msg.sender == OptionToken`. |

---

## Scope & assumptions (state plainly)

- **Excluded as upstream/covered:** the Algebra pool core (byte-identical to Algebra Integral v1.2.1, `../integrity/`), OpenZeppelin, Gnosis Safe, OZ Timelock/ProxyAdmin, and Circle USDC. Bugs in those would not be Hydrex-specific; the integrity check bounds the "doctored baseline" risk. If any of those upstreams has a latent bug, conclusions relying on them (e.g. Safe signature checks, pool `_k`) would change.
- **Read but not in the original repo:** the ve delegatecall targets `VotingEscrowV2_LockLogic 0x5c8d…` and `VotingEscrowV2_ApprovalLogic 0x4b0b…` (now saved under `contracts/ve-core/`) and the two MevX impls (recovered in `../recovered/`, unverified — 21/37 executor selectors unresolved). The ve conclusions assume the LockLogic/ApprovalLogic layout matches the impl (verified byte-identical shared libraries); if a future upgrade changed one without the other, the delegatecall-storage conclusion would change.
- **Off-chain components** (`../live-state/OFFCHAIN.md`) — the gauge-eligibility updater EOA, MEV/ALM keepers, and multisig key custody — are trusted by assumption; their compromise is a trust failure, not an unprivileged on-chain exploit, and is out of this audit's adversary model.
- This audit does not assert the system is safe against a malicious operator; it asserts that an **unprivileged** attacker has no economic or unauthorized-access exploit that survived rebuttal, given the above.
