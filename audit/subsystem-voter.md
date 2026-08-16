# Subsystem Audit — VoterV5 hub + delegatecall logic modules + PermissionsRegistry (Hydrex, Base)

Scope contracts (source under `/home/user/cetong/contracts/`):
- **VoterV5** proxy `0xc69e3ef39e3ffbce2a1c570f8d3adf76909ef17b`, impl `ve-core/VoterV5_0x9cb97233/contracts/VoterV5/VoterV5.sol`
- **VoterV5_GaugeLogic** `0x8cf73eb5…` (`ve-core/VoterV5_GaugeLogic_0x8cf7f0a3/…/VoterV5_GaugeLogic.sol`) — delegatecall target
- **VoterV5_ClaimLogic** `0x68ed6a9f…` (`ve-core/VoterV5_ClaimLogic_0x68edc21d/…/VoterV5_ClaimLogic.sol`) — delegatecall target
- **PermissionsRegistry** `0x3ea45157…` (Voter's registry) and `0x41806e1a…` (fee-dist registry) — `governance/PermissionsRegistry_0x3ea4b81d` / `_0x4180f2f7`

Verdict: **no unprivileged value-theft or unauthorized-access finding survived.** The subsystem is a hardened Thena/Solidly-derived design with snapshot-based (address-level) voting, per-tokenId anti-replay on bribes, timelock-gated roles, and a delegatecall storage layout that is provably identical across the three contracts (verified against live storage). The strongest rejected candidates and the reasoning are below.

Legend: **READ** = observed directly in source / on-chain; **INFERRED** = reasoned conclusion.

---

## 1. Entry-point table (all contracts)

### VoterV5 — 43 state-changing entry points

| # | Function | Guard (READ) | Why safe / notes |
|---|----------|--------------|------------------|
| 1 | `_init(address[],address,address,address)` | `msg.sender==minter \|\| hasRole("VOTER_ADMIN")` **and** `!initflag` | Would overwrite `minter`/`permissionRegistry`/`oToken` — but **locked**: live slot0 low byte = `01` ⇒ `initflag=true` ⇒ reverts `AlreadyInitialized`. |
| 2 | `initialize(...)` | `initializer` | Proxy already initialized; impl `_disableInitializers()` in ctor. Locked. |
| 3 | `setVoteDelay` | `VoterAdmin()` | role-gated |
| 4 | `setMinter` | `InfraAdmin()` | role-gated + contract check |
| 5 | `setOptionsToken` | `InfraAdmin()` | role-gated |
| 6 | `refreshApprovals` | `VoterAdmin()` + nonReentrant | role-gated |
| 7 | `setGaugeDepositor` | `VoterAdmin()` | role-gated |
| 8 | `setBribeFactory` | `InfraAdmin()` | role-gated |
| 9 | `setPermissionsRegistry` | `InfraAdmin()` | role-gated (registry swap) |
| 10 | `setNewBribes` | `VoterAdmin()` | role-gated + `isGauge` |
| 11 | `setInternalBribeFor` | `VoterAdmin()` | role-gated |
| 12 | `setExternalBribeFor` | `VoterAdmin()` | role-gated |
| 13 | `setFactory` | `InfraAdmin()` | role-gated |
| 14 | `setGaugeLogic` | `InfraAdmin()` | role-gated + `supportsInterface` |
| 15 | `setClaimLogic` | `InfraAdmin()` | role-gated + `supportsInterface` |
| 16 | `setProtocolName` | `VoterAdmin()` | role-gated |
| 17 | `updateWhitelistToken` | `VoterOrGaugeAdmin()` | role-gated |
| 18 | `updateWhitelistPool` | `VoterOrGaugeAdmin()` | role-gated |
| 19 | `killGauge` | `hasRole("GOVERNANCE") \|\| ==emergencyCouncil` | role-gated; refunds pending emission to minter, zeroes current-epoch weight |
| 20 | `reviveGauge` | `VoterAdmin()` | role-gated; blocks same-epoch revive (`gaugeKilledEpoch`) |
| 21 | `reset` | self, nonReentrant | operates only on `msg.sender`; epoch-safe (see §3) |
| 22 | `poke` | self, nonReentrant | self-only (no arg); reset+re-vote at current power; idempotent |
| 23 | `vote` | self, nonReentrant | power = `getPastVotes(msg.sender, active_period)` snapshot |
| 24 | `claimRewards` | delegatecall→ClaimLogic | `getReward(msg.sender)` on gauges |
| 25 | `claimRewardsFor` | delegatecall→ClaimLogic | `isClaimApprovedForAll(claimFor,msg.sender)` |
| 26 | `claimRewardTokens` | delegatecall→ClaimLogic | self |
| 27 | `claimRewardTokensFor` | delegatecall→ClaimLogic | `isClaimApprovedForAll` |
| 28 | `claimRewardTokensToRecipient` | delegatecall→ClaimLogic | `isClaimRedirectApprovedForAll` |
| 29 | `claimBribes(…,uint256)` | delegatecall→ClaimLogic | `isApprovedClaimOrOwner(msg.sender,tokenId)` |
| 30 | `claimBribes(…)` | delegatecall→ClaimLogic | `getRewardForAddress(msg.sender)` |
| 31 | `claimBribesToRecipientByTokenId` | delegatecall→ClaimLogic | `isApprovedClaimRedirectOrOwner` |
| 32 | `claimBribesToRecipientByAddress` | delegatecall→ClaimLogic | `isClaimRedirectApprovedForAll` |
| 33 | `claimFees(…,uint256)` | delegatecall→ClaimLogic | `isApprovedClaimOrOwner` |
| 34 | `claimFees(…)` | delegatecall→ClaimLogic | `getRewardForAddress(msg.sender)` |
| 35 | `claimFeesToRecipientByTokenId` | delegatecall→ClaimLogic | `isApprovedClaimRedirectOrOwner` |
| 36 | `claimFeesToRecipientByAddress` | delegatecall→ClaimLogic | `isClaimRedirectApprovedForAll` |
| 37 | `createGauge` | permissionless + nonReentrant | delegatecall→GaugeLogic; pool/token validated; creator gains no privilege |
| 38 | `createGauges` | permissionless + nonReentrant | ≤10; same validation per pool |
| 39 | `distribute(address[])` | permissionless + nonReentrant | keeper; `update_period()` then per-gauge accrual |
| 40 | `distribute(uint256,uint256)` | permissionless + nonReentrant | keeper (paged) |
| 41 | `distributeAll` | permissionless + nonReentrant | keeper |
| 42 | `distributeFees` | permissionless | pushes gauge LP fees to internal bribe |
| 43 | `notifyRewardAmount` | `msg.sender==minter` | minter-only; advances global `index` |

### VoterV5_GaugeLogic — 1 (executed only via Voter delegatecall)

| Function | Guard | Notes |
|----------|-------|-------|
| `createGauge(address,uint256)` | permissionless, GAUGE_ADMIN bypasses whitelist | Per-type pool validation against the configured DEX factory (`poolByPair`/`isPair`/`poolManager`/`customPoolByPair`); non-admin path requires whitelisted token(s) and (for INCENTIVE_CAMPAIGN) `POOL_ELIGIBILITY_ORACLE.canCreateGauge`. Bribe owner set to `teamMultisig`, not creator. |

### VoterV5_ClaimLogic — 13 (executed only via Voter delegatecall; `msg.sender` = the EOA)

| Function | VE guard (READ) | Pays to |
|----------|-----------------|---------|
| `claimRewards` | none (self) | `getReward(msg.sender)` → msg.sender |
| `claimRewardsFor` | `isClaimApprovedForAll(claimFor,msg.sender)` | claimFor |
| `claimRewardTokens` | none (self) | msg.sender |
| `claimRewardTokensFor` | `isClaimApprovedForAll(claimFor,msg.sender)` | claimFor |
| `claimRewardTokensToRecipient` | `isClaimRedirectApprovedForAll(claimFor,msg.sender)` | recipient |
| `claimBribes(…,tokenId)` | `isApprovedClaimOrOwner(msg.sender,tokenId)` | `ownerOf(tokenId)` |
| `claimFees(…,tokenId)` | `isApprovedClaimOrOwner(msg.sender,tokenId)` | `ownerOf(tokenId)` |
| `claimBribes(…)` | none (self) | msg.sender's NFTs → msg.sender |
| `claimFees(…)` | none (self) | msg.sender |
| `claimBribesToRecipientByTokenId` | `isApprovedClaimRedirectOrOwner(msg.sender,tokenId)` | recipient |
| `claimBribesToRecipientByAddress` | `isClaimRedirectApprovedForAll(claimFor,msg.sender)` | recipient |
| `claimFeesToRecipientByTokenId` | `isApprovedClaimRedirectOrOwner(msg.sender,tokenId)` | recipient |
| `claimFeesToRecipientByAddress` | `isClaimRedirectApprovedForAll(claimFor,msg.sender)` | recipient |

All 13 VE guard functions were read and are **non-trivial** (real owner/operator/approval checks, not stubbed-true) — e.g. `isClaimApprovedForAll = operator==owner || _operatorApprovals[owner][operator]`; `isApprovedClaimOrOwner = owner||forAll||getClaimApproved`. The downstream Bribe/Gauge functions additionally require `msg.sender==voter` (satisfied only because the call originates from the Voter in delegatecall context) and re-check approvals.

### PermissionsRegistry (both instances) — 8 each

| Function | Guard (READ) | Unprivileged-reachable? |
|----------|--------------|-------------------------|
| `addRole` | `onlyAdminMultisig` | no |
| `removeRole` | `onlyAdminMultisig` | no |
| `setRoleFor` | `onlyAdminMultisig` | no |
| `removeRoleFrom` | `onlyAdminMultisig` | no |
| `renounceRole` | self only (`_removeRoleFrom(msg.sender)`) | yes, but only drops *your own* role |
| `setEmergencyCouncil` | `==emergencyCouncil \|\| ==adminMultisig` | no |
| `setTeamMultisig` | `onlyAdminMultisig` | no |
| `setAdminMultisig` | `onlyAdminMultisig` | no |

On-chain (READ): `adminMultisig = 0xdf52b5a0…` (TimelockController), `teamMultisig = 0x1ae3753d…` (Safe), `emergencyCouncil = 0xcf57aa5b…` (PauseGuardian). `rolesLength=7`. No self-grant path exists; `hasRole[role][addr]` is written only inside `_setRoleFor` (onlyAdminMultisig). A `0x…dEaD` probe holds no role.

---

## 2. State read/write & cross-contract composition

### Delegatecall storage safety (READ + on-chain confirmation)
- All three contracts extend the **same** `VoterV5_Storage`. `VoterV5_Storage.sol` is **byte-identical** for Voter and GaugeLogic (`md5 4c74c54c…`); the ClaimLogic copy differs only in comment/whitespace bytes — every state-variable declaration (type, order, name) is line-for-line identical.
- The only co-bases with storage are on the **Voter** (`Initializable`+`ReentrancyGuardUpgradeable`). Solidity lays the directly-listed `VoterV5_Storage` **before** the reentrancy/initializer bases, so those land after `VoterV5_Storage`'s `uint256[47] __gap`. GaugeLogic/ClaimLogic co-bases (`ERC165`, interfaces) carry **no** storage.
- Live storage of the Voter proxy confirms `VoterV5_Storage` starts at slot 0:

| slot | value | variable |
|---|---|---|
| 0 | `…25b2ed71…01` | `initflag(=1)` + `_ve` packed |
| 1 | `0x08` | `_factories.length` |
| 2 | HYDX | `base` |
| 3 | oHYDX | `oToken` |
| 5 | 0x58b4… | `bribefactory` |
| 6 | 0xa7d6… | `minter` |
| 7 | 0x3ea4… | `permissionRegistry` |
| 8 | `0x17a`=378 | `pools.length` |
| 10 | `0x093a80` | `DURATION`=1 week |

⇒ **No layout mismatch; delegatecall cannot corrupt Voter storage.** (Assumption stated explicitly: this holds as long as `setGaugeLogic`/`setClaimLogic` — both `InfraAdmin`/timelock — only ever point at contracts compiled against this exact `VoterV5_Storage`.)

### Emission (HYDX/oHYDX) accounting — Voter internal
- Write: `_vote` → `weightsPerEpoch[active_period][pool] += poolWeight`, `totalWeightsPerEpoch[active_period] += tot`. `poolWeight = prop_i·getPastVotes(voter,active_period)/Σprop`; guarded by `Σ ≤ getPastVotes` (`if (_weight < _totalWeight) revert`).
- Write: `notifyRewardAmount` (minter) → `index += amount·1e18/totalWeightAt(prevEpoch)`.
- Read/Write: `_distribute` → `_getRewardSharesForGaugeAndUpdateSupplyIndex`: `shares = weightsPerEpoch[prevEpoch][pool]·(index−supplyIndex[gauge])/1e18`, then `supplyIndex[gauge]=index`. Double-distribute impossible (delta→0).

### ve ↔ Voter ↔ Bribe accounting reads (composition)
- `_vote`/`poke` read `IVotingEscrowV2.getPastVotes(voter, active_period)` (`edStore.getAdjustedVotes`, historical).
- Bribe balances keyed by **address**: `BribeV2.deposit(amount,voter)` → `_balances[voter][active_period]`.
- Bribe earn keyed by **tokenId** with per-token anti-replay `tokenTimestamp[tokenId][token]`. `_earnedTokenId(tokenId,token,t)` reads, all at historical `t`: `delegates(tokenId,t)`, `balanceOfNFTAt(tokenId,t)`, `balanceOfOwnerAt(delegatee,t)`, `getPastVotes(delegatee,t)`; `weight = power·1e18/delegateePower` (≤1e18 because `Σ delegated power = getPastVotes(delegatee)`).
- Gauge LP rewards (`GaugeV2._getReward`) keyed by staked LP balance; `getReward(user)` is `onlyDistribution` and pays **user** (not caller); `getReward(user,tokens)`/`getRewardToRecipient` require `msg.sender==user||DISTRIBUTION`.

---

## 3. Rejected candidates (killed before reporting)

**A. Delegatecall storage-layout corruption** — REJECTED. Identical `VoterV5_Storage` across all three + live-storage slot map confirms alignment (§2). The `Initializable`/`ReentrancyGuard` slots exist only on the Voter and sit past the shared `__gap`; the logic modules never address them.

**B. Vote double-count via transfer/re-delegate/re-vote mid-epoch** — REJECTED. Every voting-power read is `getPastVotes(_, active_period)`; `_voteDelay` reverts on the flip block, so `active_period` is always strictly in the past. Moving/delegating an NFT after `active_period` creates zero current-epoch power for the recipient, and `_vote` runs `_reset` first so re-voting nets out (`weightsPerEpoch` decremented then re-incremented). `poke()` is self-only and idempotent.

**C. Bribe double-claim via merge/split/transfer/cross-epoch** — REJECTED. `tokenTimestamp[tokenId][token]` advances past each claimed epoch (per-token, shared across owners), and each epoch's reward is computed from immutable historical checkpoints. Split mints tokenIds with no past `balanceOfNFTAt` (⇒0 for prior epochs); burn/merge only *loses* the burned token's share (documented WARN), never inflates another's. Buying an NFT with accrued bribes is documented, paid-for behavior — not unearned.

**D. Claim rewards/bribes/fees for a ve position you don't control** — REJECTED. All 13 ClaimLogic paths gate on real VE approval predicates (§1) and pay the owner/approved recipient. The address-path claims (`getRewardForAddress(msg.sender)`) only ever read the caller's own `_balances`.

**E. Self-grant a role / hijack logic module or registry** — REJECTED. Registry mutators are `onlyAdminMultisig` (a Timelock); `hasRole` is written only in `_setRoleFor`. Voter `setGaugeLogic/setClaimLogic/setPermissionsRegistry/setMinter` are `InfraAdmin` (Timelock). `_init` is locked (`initflag=1`), `initialize` is `initializer`-locked.

**F. Gauge that redirects HYDX emissions to the creator without votes** — REJECTED. Emissions are strictly `weightsPerEpoch[prevEpoch][pool]·Δindex` — zero votes ⇒ zero emission. Gauge creation confers no privilege on the creator (bribe owner = `teamMultisig`; gauge is deployed by the admin-configured factory; the max `base`/`oToken` approval goes to that trusted gauge code). Directing your own ve votes to your own gauge is the intended, stake-proportional mechanism.

**G. Permissionless gauge for a fake ERC4626 vault (VAULT_MORPHO / VAULT_EULER)** — REJECTED as economic. Vault gauge types have no DEX factory to validate `_pool` against; a non-admin can register any contract whose `asset()` returns a **whitelisted** token. But the only value a gauge yields is emissions, which require votes; a sole staker of one's own gauge captures nothing stake-independent, and no other user's funds are reachable. Robustness note, not an exploit.

**H. Fee-dist registry `0x4180` buggy `removeRole` (L-4/L-5/L-7 regressions)** — REJECTED / out of Voter trust path. The Voter uses `0x3ea4` (the fixed copy — confirmed slot 7). The `0x4180` copy still contains the old buggy `removeRole` (pops from the global `_roles` into a user's role array, no `_roleToAddresses` clear), but it is `onlyAdminMultisig` and never writes the `hasRole` permission mapping, so it cannot escalate any unprivileged caller — it only corrupts admin-side bookkeeping / can revert. Privileged-party robustness issue only.

**I. Reentrancy across the delegatecall boundary / claim↔distribute** — REJECTED. `vote/reset/poke/createGauge*/distribute*` are `nonReentrant`; downstream Gauge/Bribe transfers are `nonReentrant` and move protocol tokens (HYDX/oHYDX) or per-bribe accounting only. A malicious `_pool` probed during `createGauge` cannot re-enter any state-critical Voter function (all `nonReentrant`) nor double-create (`gauges[_pool]==0` + guard).

**J. Vote math over/under-flow or div-by-zero** — REJECTED. `Σfloor(prop_i·w/Σprop) ≤ w`; the all-dead-pool case skips the division (`isGauge&&isAlive` false for all); 0-proportion on a live gauge reverts (`InsufficientVotingPower`); 0.8.13 checked math reverts on overflow.

**K. Kill/revive ↔ reset underflow** — REJECTED. `_reset` decrements `weightsPerEpoch[t]` only when `votedInEpoch && isAlive`, and forces `_totalWeight=0` when `lastVoted<t`; `killGauge` zeroes current-epoch weight and records `gaugeKilledEpoch`; `reviveGauge` blocks same-epoch revive. All four kill/revive/reset orderings traced without underflow or double-subtract.

---

## 4. Assumptions / dependencies (out-of-subsystem, stated)
- Correctness of VotingEscrowV2 delegation accounting — specifically `Σ balanceOfNFTAt(nft,t) over nfts delegated to X == getPastVotes(X,t)` — underpins the `weight ≤ 1e18` bribe invariant. A VE checkpoint bug making delegated power exceed `getPastVotes` would let a delegator over-claim a bribe balance; that is a VE-internal property, not reachable from Voter/ClaimLogic code.
- `minter.active_period()` / `update_period()` behave monotonically (trusted Minter).
- `setGaugeLogic`/`setClaimLogic` (Timelock) only ever install modules compiled against this exact `VoterV5_Storage`.

**Bottom line: every one of the 43 + 1 + 13 + 8 + 8 entry points is either role-gated to a timelock/multisig, self-scoped and epoch-snapshot-safe, or gated by a verified VE approval; no unprivileged path takes value it did not earn or seizes privilege.**
