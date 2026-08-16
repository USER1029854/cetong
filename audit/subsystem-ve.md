# Subsystem Audit — VotingEscrow (veHYDX)

**Target:** `VotingEscrowV2Upgradeable`
**Proxy (callable):** `0x25b2ed7149fb8a05f6ef9407d9c8f878f59cd1e1` · **Impl:** `0x0fc68ce53be957a1aa779f553ad49f6068fff231`
**Holdings (READ, live):** `HYDX.balanceOf(VE) = 15,120,106.6 HYDX`; `supply() = 598,640,270.9`; `totalNftsMinted() = 120,260`.
**Chain:** Base (8453). **Compiler:** 0.8.13 (checked arithmetic — under/overflow reverts).

### Architecture (critical): logic is delegatecalled
Almost every state-changing lock function on the proxy is a thin `nonReentrant` wrapper that `delegatecall`s into two **separate, immutable** logic contracts operating on the proxy's storage:
- **LockLogic** = `VotingEscrowV2_LockLogic` @ `0x5c8dbb8f2e436175317929d1e299eb23d34eb27c` (READ, verified) — createLock*, increaseAmount, increaseUnlockTime, unlockRolling, claim, merge, split, burn.
- **ApprovalLogic** = `VotingEscrowV2_ApprovalLogic` @ `0x4b0bc0889eb524dbae36d409ff733851e9b4f63d` (READ, verified) — conduit + claim-redirect approvals.

`lockLogic`/`approvalLogic` are set only in `initialize` (initializer-guarded, already initialized) — **no `setLockLogic`/`setApprovalLogic` setter exists** (grep of ABI = NONE). They can be swapped only by a proxy upgrade (privileged, out of scope). All shared libraries (`EscrowDelegateCheckpoints`, `EscrowDelegateStorage`, `Checkpoints`, `ERC5725Upgradeable`, `VotingEscrowV2_Storage`, `SafeCastLibrary`, `Time`) are **byte-identical** between the proxy impl package and both logic packages (verified via `diff`), so the delegatecall storage layout is consistent.

### Lock model (READ)
`enum LockType { NON_PERMANENT=0, ROLLING=1, PERMANENT=2 }`
- **NON_PERMANENT**: real HYDX transferred in (`amount += V`), voting power decays over ≤ MAX_TIME (2y). Withdraw at expiry (full) or early (penalty = ½·votingPower burned).
- **ROLLING**: real HYDX transferred in (`amount += V`), non-decaying voting power = `amount`. `unlockRolling` converts it to NON_PERMANENT with a **fresh** `endTime = now + MAX_TIME` (cannot early-release; must then wait 2y or pay the early penalty).
- **PERMANENT**: underlying is **burned** (`token.burnFrom(msg.sender, V)`), credits `amount += V·(1e18/1.3e18) = V/1.3`, non-decaying. **Never** claimable/convertible (all exit paths revert). A value sink by construction.

---

## 1. Entry-point table — all 29 state-changing functions accounted for

| # | Function | Guard | Why safe (or exploitable) |
|---|----------|-------|---------------------------|
| 1 | `initialize(...)` | `initializer` | Already initialized (live w/ 15.12M HYDX). Not re-callable. |
| 2 | `createLock(value,dur,type)` | `nonReentrant` | Funds caller's own lock: `safeTransferFrom`(non-perm/rolling) or `burnFrom`(perm) from `msg.sender`. Every credit pulls tokens. |
| 3 | `createLockFor(value,dur,to,type)` | `nonReentrant` | Mints to `to`, **funded by `msg.sender`** (gift). No third-party debit. |
| 4 | `createDelegatedLockFor(...)` | `nonReentrant` | As above + sets delegatee. Funded by caller. |
| 5 | `createClaimableLockFor(...)` | `nonReentrant` | As above + sets claim-redirect approval on the **new** token only. |
| 6 | `increaseAmount(tokenId,value)` | `nonReentrant`, **no owner check (by design)** | Pulls `value` from `msg.sender`, credits target lock. Purely additive/beneficial to owner; attacker can only *donate*. Reverts on expired non-perm. |
| 7 | `increaseUnlockTime(tokenId,dur,perm)` | `checkAuthorized` | Only **extends** (`revert if new ≤ old`) or converts to ROLLING. Cannot shorten. Reverts for PERMANENT/ROLLING inputs. |
| 8 | `unlockRolling(tokenId)` | `checkAuthorized` | ROLLING→NON_PERMANENT with `endTime = now+MAX_TIME`. Cannot early-release; resets to full 2y. Reverts if not ROLLING. |
| 9 | `claim(tokenId)` | `nonReentrant` + `checkAuthorized` | Transfers underlying to `msg.sender`; reverts for PERMANENT/ROLLING. Conserves (see §3). **On-chain:** `claim(1)` from `0xdEaD` reverts `ERC721InsufficientApproval`. |
| 10 | `merge(from,to)` | `nonReentrant` + `checkAuthorized(from)` + `checkAuthorized(to)` | Type-match enforced (perm↔perm, rolling↔rolling); amounts conserved; cannot escape permanent flag. **On-chain:** `merge(1,2)` from `0xdEaD` reverts. |
| 11 | `split(weights,tokenId)` | `nonReentrant` + `checkAuthorized` | Amount conserved via remainder; lockType preserved; children minted to **owner** (not caller). Voting power only *decreases* (per-piece slope floor). |
| 12 | `burn(tokenId)` | `nonReentrant` | Requires `ownerOf==msg.sender` **and** `amount==0`. Cannot burn a value-holding lock. |
| 13 | `delegate(tokenId,delegatee)` | `checkAuthorized` | Atomic move (remove old delegatee + add new). No double-count. |
| 14 | `delegate(delegatee)` (IVotes) | `nonReentrant` | Iterates only **caller's own** tokens. |
| 15 | `delegateBatch(tokenIds,delegatee)` | per-token `_isAuthorized` check | Reverts on any unauthorized/nonexistent tokenId. |
| 16 | `checkpoint()` | (calls `globalCheckpoint`) | No-arg global advance; no value moved; idempotent. |
| 17 | `globalCheckpoint()` | `nonReentrant` | Same; decays global bias to now. |
| 18 | `checkpointDelegatee(addr)` | `nonReentrant` | Advances a delegatee checkpoint; idempotent — `lastCheckpoint` advances so slope changes are not double-applied. |
| 19 | `approve(to,tokenId)` | ERC721 (owner/operator) | Standard. |
| 20 | `setApprovalForAll(op,bool)` | ERC721 | Standard; caller's own operator set. |
| 21 | `transferFrom(from,to,id)` | ERC721 `_isApprovedOrOwner` | `_beforeTokenTransfer` resets delegatee to new owner (move). |
| 22 | `safeTransferFrom(from,to,id)` | ERC721 | `onERC721Received` fires **after** state fully consistent → no reentrancy leverage (see §2). |
| 23 | `safeTransferFrom(from,to,id,data)` | ERC721 | Same. |
| 24 | `setClaimApproval(op,bool,tokenId)` | `_setClaimApproval` requires `ownerOf==msg.sender` | ERC5725 claim approval — **not consulted by the underlying `_claim`** (which uses ERC721 auth), so grants no withdraw right. Inert for principal. |
| 25 | `setClaimApprovalForAll(op,bool)` | writes caller's own mapping | Inert for principal (as #24). |
| 26 | `setClaimRedirectApproval(to,tokenId)` | requires `ownerOf==msg.sender` | Reward-redirect only (Voter/Bribe); no ve-principal power. |
| 27 | `setClaimRedirectApprovalForAll(op,bool)` | caller's own mapping | Same. |
| 28 | `setConduitApproval(conduit,tokenId,approve)` | `nonReentrant`; token-level requires `ownerOf==msg.sender`; forAll actions operate on `msg.sender` | Grants approvals **to the conduit only**, over caller's own token/approvals; user-initiated. No third-party effect. |
| 29 | `setConduitApprovalConfig(actions,desc)` | `msg.sender` registers its **own** address as conduit (once) | Only defines what a user *would* grant if they opt in via #28. No effect on others. |

Also present (view/pure, not state-changing): `balanceOfNFT(At)`, `getPastEscrowPoint`, `getVotes`, `getPastVotes`, `getPastTotalSupply`, `totalSupply` (returns **global voting power**, not NFT count), `lockDetails`, `tokenURI`, ERC721Enumerable views, etc. — no value movement.

---

## 2. State read/write & work-composition analysis

**Core state:** `__lockDetails[id]{amount,startTime,endTime,lockType}`, `supply`, `_payoutClaimed[id]`, and `edStore` = {`_globalCheckpoints`, `globalSlopeChanges`, `_escrowCheckpoints[id]`, `_delegateCheckpoints[addr]`, `_escrowDelegateeAddress[id]`, `delegateeSlopeChanges[addr]`}.

**Money paths:** (a) `claim` → `token.safeTransfer` to caller; (b) Minter `calculate_rebase(week, weeklyMint, _ve.supply(), hydxSupply)` mints rebase → RewardsDistributorV2 distributes per **`balanceOfNFTAt(id,week)/getPastTotalSupply(week)`** (READ, `RewardsDistributorV2.sol:171-219`). So the rebase-share invariant is **per-escrow checkpoint vs global checkpoint consistency**, which `checkpoint()` maintains by construction (`global += (uNewPoint − uOldPoint)` on every escrow change; both pushed in the same call).

**Compositions attempted (all conserve / are blocked):**
- **create → claim round-trip:** `supply` += V then −=(claim+penalty)=amount; `token` out (transfer+burn)=amount held. Balanced.
- **increaseUnlockTime(ROLLING) → unlockRolling → claim:** conversion resets `endTime=now+MAX_TIME`, so votingPower≈amount ⇒ early penalty ≈ amount/2. **Does not** dodge the penalty; cannot early-release a permanent-class lock.
- **merge NON_PERMANENT→ROLLING (upgrade to max-lock):** allowed (only `from==ROLLING && to!=ROLLING` and perm/non-perm mixes are blocked). Result voting power = combined `amount`, but both sides were real-token-backed and `endTime` bounded by `now+MAX_TIME` ⇒ `bias ≤ amount`. Legitimate max-lock, not minting.
- **split of PERMANENT:** `duration=0`, children created SPLIT_TYPE (no burn/transfer) but `lockType` preserved ⇒ children stay PERMANENT, `Σ amount_i = amount` exactly (permanent has no slope rounding). Cannot turn permanent into withdrawable.
- **split of NON_PERMANENT:** `Σ value_i = amount` (last piece = remainder); `Σ floor(value_i/MAX_TIME) ≤ floor(amount/MAX_TIME)` ⇒ total voting power only *drops*. `supply` net change = 0.
- **delegate A→B then transfer:** each is a symmetric move (remove-from-old = add-to-new using the same decayed escrow point). No epoch double-count.
- **deposit → weekly rebase → withdraw:** rebase reads **historical past-week** escrow checkpoints; a lock created mid-week has no checkpoint at the prior week cursor (returns 0), and a lock claimed before the next cursor has `amount=0` there. Flash-locking earns nothing.

**ERC721 reentrancy (emphasized in scope):** `_createLock` (and split's children) use OZ **`_mint`** — `ERC721Upgradeable._mint` (READ, line 269) does **not** call `_checkOnERC721Received`; only `_safeMint` does, and it is never used. `safeTransferFrom`'s `onERC721Received` fires **after** `_transfer` fully completes (ownership + delegatee move done), so a malicious receiver sees fully-consistent state — reentering `claim/merge/split/...` is ordinary sequential use (each is additionally `nonReentrant`). HYDX itself is plain `ERC20Permit+ERC20Burnable+Ownable` with **no transfer/burn callbacks** (READ `HydrexToken.sol:19`), so `safeTransfer/burn/burnFrom` inside `_claim`/`_updateLock` cannot reenter. **No half-updated-state reentrancy path found.**

---

## 3. Surviving findings

**None survived.**

Invariant checks (all hold):
- *Owner can never withdraw more than locked:* aggregate withdrawable = Σ(NON_PERMANENT+ROLLING `amount`) = contract HYDX balance (every such credit did a real `safeTransferFrom`; `claim` removes `amount` and burns the penalty from it). Confirmed by live `balanceOf(VE)=15.12M` backing exactly the non-burned locks; PERMANENT principal is burned and unbacked-by-design but also unclaimable.
- *Permanent lock cannot be withdrawn/decayed early:* PERMANENT reverts in `claim` (`PermanentLock`), `increaseUnlockTime` (`PermanentLock`), `unlockRolling` (`NotPermanentLock`), and merge type-guards; split preserves the flag. ROLLING can only convert via `unlockRolling` to a fresh `now+MAX_TIME` decay.
- *Voting weight not mintable without locking / not double-counted:* `supply` and all checkpoint biases only move on real deposits or symmetric moves; `global == Σ escrow` by construction; delegate is a move.
- *Cannot move/burn/withdraw an unowned NFT:* every mutating path is `checkAuthorized`/`ownerOf`-gated (live-verified: unauthorized `claim`/`merge` revert `ERC721InsufficientApproval`).

### Closest rejected candidates

**R1 — `supply` over-counts PERMANENT locks by 1.3× → Minter rebase inflation.**
`_LockLogic.sol:109-138` (`_updateLock`): for PERMANENT it does `supply += V` while `amount += V/1.3` and `burnFrom(V)`. Live divergence is real and large: `supply()=598.6M` vs `balanceOf(VE)=15.12M` (genesis airdrop permanent-locks, Minter `_initialize` line 283). `MinterUpgradeableV4.calculate_rebase` feeds `_ve.supply()` into the weekly rebase size (READ line 332). **Rejected as attacker-profitable:** the only lever an unprivileged attacker has on `supply` is real deposits, and a PERMANENT deposit *burns V to obtain only V/1.3 non-decaying power* — strictly dominated by a ROLLING deposit (V→V power, recoverable) which inflates `supply` by the same V. The extra rebase is minted to the whole ve pool and split by voting power (`balanceOfNFTAt/getPastTotalSupply`, amount-based and fair), so no disproportionate/stake-independent capture. It is a tokenomics/emission-sizing quirk, not value theft. *(INFERRED: exact `EmissionSchedule.calculateRebaseAmount` curve not fully traced — out of ve scope; conclusion holds for any monotone-in-supply formula because the attacker's own lever is dominated.)*

**R2 — early-exit penalty = 0 for sub-slope-threshold dust.**
`_calculateEarlyExitPenalty` returns `(0, deposited)` when `balanceOfNFT==0`; because `slope = amount/MAX_TIME` floors to 0 for `amount < MAX_TIME = 63,072,000 wei` (~6.3e-11 HYDX), such a lock has 0 voting power and pays no early penalty. **Rejected:** to abuse at scale you must `split` a real position into ~`V/6.3e7` (≈1e13 for 1k HYDX) sub-threshold NFTs — gas-infeasible — and even then you only recover *your own principal* early (no over-withdrawal); it is penalty avoidance on dust, not value extraction.

**R3 — ERC721-approved operator can `claim`/`merge` value to itself.**
`_claim` transfers to `msg.sender`, and `merge(from=victim, to=operator's)` moves value into the operator's token, both gated only by ERC721 `checkAuthorized`. **Rejected:** an ERC721-approved operator can already `transferFrom` the NFT to itself (full control), so claiming/merging to itself is no escalation; and `split` deliberately mints children to `ownerOf`, not the caller. Requires the victim's prior approval → not an unprivileged attack.

---

## 4. Sources / assumptions

- **READ (source):** proxy impl `VotingEscrowV2Upgradeable.sol`; delegatecall targets `VotingEscrowV2_LockLogic` (`0x5c8d…`) and `VotingEscrowV2_ApprovalLogic` (`0x4b0b…`), both Etherscan-verified and fetched; all shared libraries diff-identical to the repo copies. `ERC721Upgradeable._mint`, `HydrexToken.sol`, `RewardsDistributorV2.sol`, `MinterUpgradeableV4.sol` read for the money-path.
- **READ (live, Base RPC):** `supply`, `balanceOf(VE)`, `totalNftsMinted`, and unauthorized `claim(1)`/`merge(1,2)` from `0x…dEaD` (both revert `0x177e802f` = `ERC721InsufficientApproval`).
- **INFERRED / assumptions:** exact `EmissionSchedule.calculateRebaseAmount` and `RewardsDistributorV2` weekly-cursor internals treated as out-of-subsystem (their ve reads are amount-based historical checkpoints — verified). Checkpoint library is the OZ v5-derived Trace with same-key overwrite; accumulation-within-block verified by re-read-modify-push pattern. Proxy assumed already-initialized (consistent with live holdings). Delegatecall storage-layout equivalence assumed from the byte-identical library/`_Storage` diff.
