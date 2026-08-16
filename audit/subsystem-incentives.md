# Subsystem audit — Incentives / Bribes / Fee-distribution + Solidly Pair (Hydrex, Base)

Scope contracts (source under `/home/user/cetong/contracts/`):

| Contract | Impl source | Deployed at |
|---|---|---|
| BribeV2 | `liquidity/BribeV2_0x6225a28d/contracts/VoterV5/BribeV2.sol` | internal bribe `0xb69b1c48…`, external bribe `0x3fde14f3…` |
| GaugeIncentiveCampaign | `liquidity/GaugeIncentiveCampaign_0x22d2480d/contracts/GaugeIncentiveCampaign.sol` (+ base `GaugeV2.sol`) | communityVault `0xac396cab…` |
| IncentiveCampaignManager | `liquidity/IncentiveCampaignManager_0xa2898cef/contracts/IncentiveCampaignManager.sol` | `0x416d1a1b…` |
| GaugeFactoryIncentiveCampaign | `liquidity/GaugeFactoryIncentiveCampaign_0x30d5983e/contracts/factories/GaugeFactoryIncentiveCampaign.sol` | `0xbe50ae49…` |
| BribeFactoryV4 | `ve-core/BribeFactoryV4_0x25f4b970/contracts/factories/BribeFactoryV4.sol` | proxy `0x58b4f302…` |
| Pair (volatile HYDX/USDC) | `liquidity/Pair_0x605a2e1d/contracts/Pair.sol` | `0x605abd18…` |
| PairFees | `liquidity/Pair_0x605a2e1d/contracts/PairFees.sol` | `0xada56cd4…` |

**Bottom line:** no economic or unauthorized-access finding survived in BribeV2, the Pair, PairFees, GaugeIncentiveCampaign, IncentiveCampaignManager, or BribeFactoryV4. One **LOW** finding survives: `GaugeFactoryIncentiveCampaign.createGaugeV2` has no access control (unauthorized action; impact limited to orphan-gauge spam + gas-DoS of one admin batch function). One **hardening / cross-subsystem coupling** is flagged: BribeV2 re-derives per-NFT reward weight from VotingEscrowV2 with no `<=1e18` cap, so its value-conservation depends entirely on a ve delegation invariant that lives in a different subsystem.

On-chain confirmations (Base, `eth_call`): internal bribe `voter=0xc69e…`(VoterV5), `minter=0xa7d6…`(MinterV4), `bribeFactory=0x58b4…`(BribeFactoryV4), `ve=0x25b2…`. Voter `_epochTimestamp() == IMinter.active_period()` (VoterV5.sol:1043-1044) — identical to the epoch key BribeV2 uses, so deposit-amount timing, bribe storage key, and reward weight-timestamp are the same Thursday boundary. Pair: `token0=HYDX 0x00000e7e…`, `token1=USDC 0x833589fc…`, `stable=false`, `getFee()=180` (0.18%), `fees=PairFees 0xada5…`.

---

## 1. Entry-point accounting (all state-changing externals)

### BribeV2 (17) — `BribeV2.sol`
| Fn | Guard | Verdict |
|---|---|---|
| `deposit(uint,address)` :256 | `msg.sender==voter` :258 | SAFE — only VoterV5 credits vote balance |
| `withdraw(uint,address)` :271 | `msg.sender==voter` :273 | SAFE — silent no-op if `amount>balance` :277 keeps `Σbalances==totalSupply` |
| `getReward(uint,address[])` :303 | `isApprovedOrOwner(sender,tokenId)` :304, pays `ownerOf` | SAFE |
| `getReward(address[])` :310 | iterates `msg.sender`'s NFTs, pays self | SAFE |
| `getRewardForOwner(uint,address[])` :320 | `msg.sender==voter` :321, pays `ownerOf` | SAFE — Voter checks ownership (see §4) |
| `getRewardForAddress(address,address[])` :327 | `msg.sender==voter` :328 | SAFE |
| `getRewardToRecipient(uint,address[],address)` :336 | `isApprovedClaimRedirectOrOwner ‖ voter` :337 | SAFE |
| `getRewardForAddressToRecipient(...)` :342 | `isClaimRedirectApprovedForAll ‖ voter` :347 | SAFE |
| `notifyRewardAmount(address,uint)` :357 | `isRewardToken` :358; pulls from caller | SAFE — permissionless by design (adding bribes = donation) |
| `addRewardToken(s)` :382/390 | `onlyAllowed` (owner‖factory) | PRIV |
| `recoverERC20AndUpdateData` :402 | `onlyAllowed` | PRIV (documented WARN — owner can drain) |
| `emergencyRecoverERC20` :417 | `onlyAllowed` | PRIV (documented WARN) |
| `setVoter/​setMinter/​setOwner` :424/430/438 | `onlyAllowed` | PRIV |
| `initialize` :64 | `initializer`; deployed atomically by factory | SAFE |

### GaugeIncentiveCampaign (16) — `GaugeIncentiveCampaign.sol` + `GaugeV2.sol`
| Fn | Guard | Verdict |
|---|---|---|
| `claimFees()` (GaugeV2:623 → override `_claimFees` :482) | `nonReentrant`, permissionless | SAFE — sweeps gauge token0/1 balance to the gauge's registered internal bribe (`IVoterV5.internal_bribes(this)`); intended destination, attacker gains nothing |
| `notifyRewardAmount(address,uint)` :250 | `onlyDistribution`, `isNotEmergency`, whitelisted token :254 | SAFE — only VoterV5 routes emissions |
| `getReward*` / `deposit*` / `withdraw*` / `earned` | `pure … revert StakingDisabled/RewardsDisabled` :124-234 | SAFE — staking disabled |
| `_withdrawFromCentralPoolSafe` (GaugeV2:693) | `require(msg.sender==address(this))` | SAFE — self-call only |
| `activate/stopEmergencyMode`, `sweepTokens`, `setCampaignManager`, `setDistribution`, `setPermissionsRegistry`, `revokeCentralTokenPool` | `onlyOwner` | PRIV |
| `acceptOwnership`/`transferOwnership`/`renounceOwnership` | Ownable2Step | PRIV |
| `initialize` :88 | `initializer` | SAFE |

### IncentiveCampaignManager (14) — all config; every setter `onlyOwner`, `initialize` initializer, `acceptOwnership` pending-owner. **PRIV / SAFE.** `getEffectiveConfig` (view) is read by the gauge only.

### GaugeFactoryIncentiveCampaign (14) — `GaugeFactoryIncentiveCampaign.sol`
| Fn | Guard | Verdict |
|---|---|---|
| **`createGaugeV2(...)` :69** | **NONE** | **FINDING (LOW) — see §3** |
| `activate/stopEmergencyMode`, `setDistribution`, `setGaugeRewarder`, `setCampaignManagerForGauges`, `setPermissionsRegistry(ForGauges)`, `setCentralTokenPool`, `setIncentiveCampaignManagerDefault` | `onlyAllowed` (owner ‖ GAUGE_ADMIN) | PRIV |
| `acceptOwnership`/`transferOwnership`/`renounceOwnership`, `initialize` | Ownable2Step / initializer | PRIV/SAFE |

### BribeFactoryV4 (18) — `BribeFactoryV4.sol`
| Fn | Guard | Verdict |
|---|---|---|
| `createBribe` :94 | `msg.sender==voter ‖ owner()` :95 | SAFE |
| `addRewardTo(s)Bribe(s)` | `onlyAllowed` (owner‖BRIBE_ADMIN) | PRIV |
| `setBribeVoter/Minter/Owner`, `recoverERC20From`, `recoverERC20AndUpdateData` | `onlyOwner` | PRIV (owner can drain bribes — documented) |
| `setVoter/setPermissionsRegistry/push/removeDefaultRewardToken` | `owner()` | PRIV |
| `acceptOwnership/transfer/renounceOwnership`, `initialize` | Ownable2Step / initializer | PRIV/SAFE |

### Pair (11) — `Pair.sol`
| Fn | Guard | Verdict |
|---|---|---|
| `swap` :356 | `lock`; K-check `_k(balAfterFee)>=_k(reserve)` :384 | SAFE — fee removed to PairFees *before* K-check; xy=k enforced |
| `mint` :311 / `burn` :334 | `lock`; pro-rata; `MINIMUM_LIQUIDITY` lock | SAFE (standard UniV2/Solidly) |
| `claimFees()` :147 | permissionless; pays `msg.sender` `claimable0/1` then zeroes | SAFE — index accounting; JIT self-unprofitable |
| `skim` :392 | `lock`; sends `balance-reserve` | SAFE — only donations; no fee held in Pair |
| `sync` :399 | `lock`; reserves=balances | SAFE — donations benefit LPs, not caller |
| `setFee(uint)` :141 | `msg.sender==factory.feeManager()` | PRIV |
| `approve/transfer/transferFrom/permit` | standard ERC20 | SAFE |

### PairFees (1) — `claimFeesFor(address,uint,uint)` :29, guard `require(msg.sender==pair)` :30. **SAFE.**

---

## 2. State read/write & work-composition map (the parts that matter)

### BribeV2 epoch accounting (READ from source)
- Storage: `_balances[owner][T]`, `_totalSupply[T]`, `rewardData[token][T].rewardsPerEpoch`, `tokenTimestamp[tokenId][token]`. `T` is always `IMinter.active_period()` (a Thursday, multiple of `WEEK`).
- **Writers:** `deposit`/`withdraw` (VoterV5 only) mutate `_balances[user][T]`+`_totalSupply[T]` **for the current `T` only**; `notifyRewardAmount` adds to `rewardData[token][T]` for current `T`. Once `active_period` advances, epoch `T` is frozen forever.
- **Readers (claim):** `earned`/`_earnedWithTimestampTokenId` loop epochs `[tokenTimestamp … active_period)` — **strictly-past epochs only** (line 152-159 / 185-192), i.e. never the still-mutable current epoch. `tokenTimestamp[tokenId][token]` advances past each processed epoch ⇒ no double-claim.
- **Per-NFT reward** (`_earnedTokenId` :215):
  `reward = rewardsPerEpoch(T)/totalSupply(T) × _balances[D][T] × balanceOfNFTAt(nft,T)/getPastVotes(D,T)`, where `D = delegates(nft,T)`.
  Every ve read (`delegates`, `balanceOfNFTAt`, `getPastVotes`) is at the **historical** boundary `T`; the deposited `_balances[D][T]` is set by the Voter as `_voteProportions·getPastVotes(D,T)/Σprop` (VoterV5.sol:698,712,725) — also anchored at `T`. Snapshot-consistent.

### Vote-weight-at-epoch conservation (INFERRED from the two contracts together)
Σ over all NFTs of `reward = rewardsPerEpoch·Σ_D[ (balance_D/totalSupply)·(Σ_{nft→D} power_nft / pastVotes_D) ]`. This equals `rewardsPerEpoch` **iff** `Σ_{nft→D} balanceOfNFTAt(nft,T) == getPastVotes(D,T)` for every delegatee `D`. That equality is a **VotingEscrowV2** property (out of this subsystem). See §3-B.

### Pair fee-index (READ)
- `swap` takes `amountIn·fee/100000` out to PairFees via `_update0/_update1` (:164/:174), bumping `index0/index1` by `amount·1e18/totalSupply`; then re-reads balances and enforces K on the post-fee balances (:381-384). Reserves set to post-fee balances (:387) ⇒ pool product preserved, fee funded by trader.
- LP fee claim: `_updateFor(recipient)` (:186) credits `balance·(index-supplyIndex)/1e18`; called on every mint/burn/transfer *before* the balance change ⇒ new LPs get `supplyIndex=index` (no back-fees), leavers settled. `claimFees` (:147) zeroes `claimable` before paying from PairFees. Σ claimable ≤ Σ fees in (rounding down keeps dust in PairFees). No drain, no pre-join claim.

---

## 3. Surviving findings

### A. `GaugeFactoryIncentiveCampaign.createGaugeV2` — missing access control (LOW / unauthorized action)

**Code:** `GaugeFactoryIncentiveCampaign.sol:69-96`
```solidity
function createGaugeV2(address, address, address _token, address _distribution, address, address, bool)
    external returns (address) {                 // <-- no onlyAllowed / no msg.sender==voter
    require(_token != address(0), "zero token");
    require(_distribution != address(0), "zero distribution");
    require(defaultIncentiveCampaignManager != address(0), "campaign manager not set");
    ... BeaconProxy newGauge = new BeaconProxy(...);
    last_gauge = address(newGauge); __gauges.push(last_gauge); ...
}
```
Every other mutating function on this factory is `onlyAllowed` (owner ‖ GAUGE_ADMIN); the sibling gauge-creation path in the Voter is reached only through governance/oracle gating (`VoterV5_GaugeLogic.createGauge`). This function is world-callable.

**Exploit path & why impact is bounded:**
1. Anyone calls `createGaugeV2(x, x, attackerToken, attackerDistribution, x, x, x)` → deploys a fresh `GaugeIncentiveCampaign` BeaconProxy and pushes it into `__gauges`.
2. The orphan gauge is **never registered in VoterV5**: the Voter's `createGauge` consumes the *return value* of `createGaugeV2` (VoterV5_GaugeLogic.sol:280) and writes `gauges[_pool]/internal_bribes/isGauge` from bribes *it* created — it never reads the factory's `last_gauge`/`__gauges`. So no real fee/emission flow can be diverted to the orphan.
3. The orphan's `owner()` is the **factory** (BeaconProxy runs `initialize` with `msg.sender=factory` ⇒ `__Ownable_init` sets owner=factory), so the attacker cannot even drive the orphan's `onlyOwner`/`onlyDistribution`-limited functions; it holds no funds. No token theft.

**Residual impact:** unbounded growth of `__gauges` ⇒ `setPermissionsRegistryForGauges()` (:186, loops all `__gauges`) can be pushed past the block gas limit, bricking that one admin convenience function; plus registry/enumeration pollution. Each orphan costs the attacker a full BeaconProxy deploy, so it is expensive, low-value griefing.

**Fix:** add `onlyAllowed` (or `require(msg.sender == IVoterV5(...).*` / the registered voter) to `createGaugeV2`, matching the rest of the factory.

---

### B. BribeV2 reward weight is uncapped — conservation depends on an out-of-subsystem ve invariant (HARDENING / cross-subsystem coupling; NOT confirmed exploitable in-scope)

**Code:** `BribeV2.sol:231-237`
```solidity
uint256 _weight = (_power * 1e18) / _delegateePower;          // _power = balanceOfNFTAt(nft,T)
...                                                           // _delegateePower = getPastVotes(D,T)
uint256 _rewards = (((_rewardPerToken * _balance) / 1e32) * _weight) / 1e18;   // no _weight<=1e18 cap
```
**READ (in-scope fact):** BribeV2 re-derives each NFT's share of a delegatee's deposited vote-balance from live ve checkpoint reads and applies **no upper bound** on `_weight` and no check that co-delegators' weights sum to ≤1e18. If ever `balanceOfNFTAt(nft,T) > getPastVotes(D,T)` (single-NFT case) or `Σ_{nft→D} balanceOfNFTAt(nft,T) > getPastVotes(D,T)` (multi-delegator case), total payouts for epoch `T` exceed `rewardsPerEpoch(T)`, over-distributing the bribe/fee tokens (the internal bribe is the sink for **100% of the pool's swap fees**, so over-distribution = draining real USDC/HYDX from later claimants). Because rewards are paid eagerly per claim, the first claimants get paid and the shortfall lands on the last claimant (revert / stuck).

**INFERRED / assumption:** whether the ve inequality is reachable is a **VotingEscrowV2** question (a different subsystem). With a correct ve, `delegates(nft,T)=D` guarantees `balanceOfNFTAt(nft,T)` is included in `getPastVotes(D,T)`, so every weight ≤1e18 and they sum to exactly 1e18 — perfect conservation. I could **not** construct a violation read-only and did not audit ve here. I am therefore *not* claiming a confirmed exploit; I am flagging the coupling and the absent defensive cap.

**Fix (cheap, defense-in-depth):** `if (_weight > 1e18) _weight = 1e18;` bounds the single-NFT case for free. A fuller fix records each tokenId's actual vote contribution at deposit time instead of re-deriving it from ve at claim time, removing the cross-subsystem trust entirely.

---

## 4. Killed candidates (why each is not a finding)

- **Classic Solidly bribe double-claim / claim-after-withdraw / vote-at-epoch-edge.** BribeV2 does **not** use the classic `balanceCheckpoints`/`getPriorBalanceIndex` binary search; it uses epoch-timestamp-keyed mappings (`_balances[owner][T]`, `_totalSupply[T]`). Past epochs are immutable once `active_period` advances; `earned` only sums epochs `< active_period`; `tokenTimestamp[tokenId][token]` monotonically advances (per-tokenId, survives NFT transfer) ⇒ no double-claim, no claim for the still-open epoch, no claim for weight not held at `T`. Re-vote/poke/reset within an epoch nets to the last vote (deposit adds, withdraw subtracts the same `votes[voter][pool]`). Buying an NFT with unclaimed past rewards is legitimate (rewards follow the NFT).
- **Directly crediting vote balance or claiming another user's tokenId.** `deposit`/`withdraw` are `msg.sender==voter`-gated; `getReward` variants gate on `isApprovedOrOwner` / `isApprovedClaimRedirectOrOwner`, or `msg.sender==voter` — and the Voter's ClaimLogic (VoterV5_ClaimLogic.sol:99-205) checks `isApprovedClaimOrOwner`/`isApprovedClaimRedirectOrOwner`/`isClaimRedirectApprovedForAll` before every forwarded call; BribeV2 always pays `ownerOf(tokenId)` or an approval-gated redirect. No bypass.
- **`notifyRewardAmount` permissionless.** Adding a whitelisted reward token to the current epoch is a donation shared pro-rata by that epoch's voters; attacker cannot recover more than their own vote share ⇒ never profitable. `firstBribeTimestamp` front-run only shifts the first-claim loop start; no over-claim.
- **Sole/dominant voter captures ~100% of an epoch's fees for tiny stake; `claimFees()` timing assigns accumulated fees to the current epoch.** Both are inherent ve(3,3) design: payout share = your `_balances[you][T]/totalSupply[T]`, i.e. stake-proportional, not stake-independent; the "which epoch gets the accumulated fees" lever is temporal/ordering (excluded) and still splits pro-rata among that epoch's voters.
- **Pair `swap` K / fee-on-input.** Fee is transferred to PairFees *before* the `_k(balAfterFee) >= _k(reserveBefore)` check (:379-384) and reserves are set to post-fee balances ⇒ constant product never decreases, fee paid by trader, no free reserve extraction. Reentrancy into `swap/mint/burn/skim/sync` blocked by `lock`; reentering the unlocked `claimFees`/`transfer` during a swap hook sees an un-bumped index ⇒ no double fee.
- **`skim`/`sync`/donation games.** Pair never holds accrued fees (moved to PairFees immediately), so `skim` (`balance-reserve`) and `sync` only move genuine donations; the donor loses, nobody steals.
- **Late-LP claiming pre-join fees.** `_updateFor` runs before every balance change and sets a brand-new LP's `supplyIndex = index` (no retroactive `claimable`). Rounding is down; PairFees keeps the dust; `address(0)`'s `MINIMUM_LIQUIDITY` share is permanently locked (standard).
- **JIT liquidity to skim fees.** Only accrues fees from swaps occurring while you hold LP; self-generating the swap costs more fee than your LP share recovers. Cross-user JIT is front-running (excluded).
- **GaugeIncentiveCampaign `_claimFees` sweeping full balance / routing to wrong destination.** `internal_bribe()` is read from VoterV5 (`internal_bribes(this)`) — attacker-immutable; `claimFees()` only moves the gauge's own community-fee balance to the correct bribe. Donations to the gauge get swept to voters (donor's loss), not to the attacker. `notifyRewardAmount`/`sweepTokens` are `onlyDistribution`/`onlyOwner`.
- **Beacon-impl `initialize` front-run.** Proxies are initialized atomically at deploy; initializing a shared implementation contract cannot affect proxy storage and the impls contain no delegatecall/selfdestruct.
- **`setFee` with no upper bound.** `feeManager`-gated (privileged, excluded); worst case is swap DoS, not extraction.

---

### Assumptions / notes
- VotingEscrowV2, VoterV5, MinterV4 are treated as correct trusted dependencies (different subsystems); the only place that matters is §3-B (the ve delegation-sum invariant) and the confirmation that VoterV5 gates ownership before hitting BribeV2's `voter` fast-path (verified, §4).
- `_epochTimestamp()==active_period()` verified on-chain; if a future Minter/Voter change desynced them, the deposit-amount vs weight-timestamp anchoring in §2 would break — worth a regression check.
- Line numbers reference the in-repo sources listed in the header table.
