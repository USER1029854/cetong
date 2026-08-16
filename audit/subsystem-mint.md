# Subsystem audit — Minter + EmissionSchedule + RewardsDistributor (rebase)

Hydrex ve(3,3) on Base. Scope contracts (impl sources):
- **MinterUpgradeableV4** — proxy `0xa7d64625f45548a19b2a19e28e7546bb2839003e`, impl `mint-authority/MinterUpgradeableV4_0xde97d219/contracts/MinterUpgradeableV4.sol`
- **RevisedPhasedEmissionSchedule** — `0x5aaa65af617fa50041325f46ecee5613aaff2727`, `mint-authority/RevisedPhasedEmissionSchedule_0x5aaa2727/contracts/emission-schedule/RevisedPhasedEmissionSchedule.sol`
- **RewardsDistributorV2** — `0x6fca200fe1f71be1b8714acfb5e9d3a147cced42`, `ve-core/RewardsDistributorV2_0x6fcaed42/contracts/VoterV5/RewardsDistributorV2.sol` (holds **799,028 HYDX**)
- Trusted read source: **VotingEscrowV2Upgradeable** `0x25b2…` + `libraries/EscrowDelegateCheckpoints.sol` (in scope only as the oracle the rebase trusts)

**Bottom line: no unprivileged over-mint / over-claim / privilege-escalation finding survived.** All 30 entry points are either correctly role-gated, or permissionless but value-neutral. On-chain state confirms initializers are exhausted (`_initialized = 2`) and every admin role is a non-zero privileged address. The surviving issues are one **Low correctness/fund-strand footgun** in `_claim` and **griefing** from missing caller-auth on `claim*`; plus centralization notes (owner can drain, governor can re-mint) that are explicitly out of the exploitation scope.

READ = confirmed by reading the deployed source and/or on-chain `eth_call`. INFERRED = reasoned, not exhaustively proven on-chain.

---

## 1. Entry-point table (all 30 accounted for)

### MinterUpgradeableV4 — 19 state-changing
| # | Entry point | Guard | Verdict |
|---|---|---|---|
| 1 | `update_period()` | permissionless keeper; `nonReentrant` + `active_period` guard | **SAFE.** One mint/week, split is `team≤5% + rebase≤26% + gauge=remainder`; no double-mint, no over-mint. See §3-A. |
| 2 | `_initialize(address[],uint256[],uint256)` | `require(governor==msg.sender)` | SAFE from unprivileged (reverts). *Note: re-callable by governor → arbitrary re-mint; centralization, §4.* |
| 3 | `initialize(...)` | OZ `initializer` | SAFE — `_initialized=2`, reverts. |
| 4 | `reinitializeV4(address,address)` | OZ `reinitializer(2)` | SAFE — `_initialized=2`, reverts ("already initialized"). Front-run **killed**. |
| 5 | `setGovernor` / `acceptGovernor` | `governor` / `pendingGovernor` | SAFE (pending=0). |
| 6 | `setTeamRate(uint256)` | `governor`, `≤MAX_TEAM_RATE(50)` | SAFE. |
| 7 | `setEmissionSchedule(address)` | `governor` + ERC165 check | SAFE. |
| 8 | `setTeamRecipient`/`acceptTeamRecipient` | `teamAdmin`/`pending` | SAFE. |
| 9 | `setTeamAdmin`/`acceptTeamAdmin` | `teamAdmin`/`pending` | SAFE. |
| 10 | `setVoter(address)` | `teamAdmin` | SAFE. |
| 11 | `setEmissionsGovernor(address)` | `teamAdmin` | SAFE. |
| 12 | `setRewardDistributor(address)` | `teamAdmin` | SAFE. |
| 13 | `setInitialSupply(uint256)` | `onlyOwner` | SAFE. |
| 14 | `transferOwnership`/`acceptOwnership`/`renounceOwnership` | `onlyOwner`/`pendingOwner` | SAFE. |

### RevisedPhasedEmissionSchedule — 2
| # | Entry point | Guard | Verdict |
|---|---|---|---|
| 15 | `adjustTailEmission(uint256,bool)` | `onlyGovernance`, `≤2%` cap, 1×/epoch | SAFE from unprivileged. |
| 16 | `transferGovernance(address)` | `onlyGovernance` | SAFE. |

### RewardsDistributorV2 — 9
| # | Entry point | Guard | Verdict |
|---|---|---|---|
| 17 | `claim(uint256)` | **none** (permissionless) | No theft — reward always routed to `ownerOf(tokenId)`. Griefing + strand footgun. §3-B/§3-C. |
| 18 | `claim_many(uint256[])` | none | Same as claim, per token → each token's owner. SAFE from theft. |
| 19 | `claimInto(uint256,uint256)` | `require(ownerOf(tok)==ownerOf(recv))` + recv permanent | No theft (same owner). Griefing only. |
| 20 | `claimManyInto(uint256[],uint256)` | same-owner per token + recv permanent | SAFE from theft. |
| 21 | `checkpoint_token()` | `assert(msg.sender==depositor)` | SAFE — depositor = Minter; unprivileged reverts (panic 0x01). |
| 22 | `checkpoint_total_supply()` | none | SAFE — only fires `ve.checkpoint()` + advances `time_cursor`; cannot alter historical `getPastTotalSupply`/`balanceOfNFTAt`. §3-D. |
| 23 | `setDepositor(address)` | `require(msg.sender==owner)` | SAFE. |
| 24 | `setOwner(address)` | `require(msg.sender==owner)` | SAFE. |
| 25 | `withdrawERC20(address)` | `require(msg.sender==owner)` | SAFE from unprivileged. *Owner can drain 799K — centralization, §4.* |

On-chain roles (READ, `eth_call`): Minter `governor=teamAdmin=0xdf52…898f`, `teamRecipient=0xd9e9…50af`, `owner=0x1ae3…0311`, `emissionsGovernor=0x0`. RDIST `owner=0x1ae3…0311`, `depositor=0xa7d6…003e` (=Minter). Schedule `governance=0x1ae3…0311`. HYDX `owner=Minter`. All non-zero. `useInitialSupply=1`, `initialSupply=500,000,000e18` (emission base is fixed, not live supply).

Unprivileged reverts confirmed by simulation from `0xdEaD`: `checkpoint_token()`→assert; `withdrawERC20`→revert; `reinitializeV4`→"already initialized"; `_initialize`→revert(not governor). `checkpoint_total_supply()` and `update_period()` succeed but are value-neutral (`update_period` returned `active_period` without minting — week not elapsed).

---

## 2. State read/write + cross-contract composition

### The reads the rebase trusts (the crux of the whole subsystem)
`_claim` (RewardsDistributorV2.sol:151-186) computes each week's share as:
```
to_distribute += balanceOfNFTAt(tokenId, w) * tokens_per_week[w] / getPastTotalSupply(w)   // w = week boundary, integer division
```
Backing implementations (VotingEscrowV2Upgradeable.sol → EscrowDelegateCheckpoints.sol):
| VE function | Impl | Semantics |
|---|---|---|
| `balanceOfNFTAt(id,w)` | `getAdjustedEscrowBias` (L524) → `getAdjustedEscrow` (L544) | `upperLookupRecent(w)` on the NFT's checkpoint trace, decays `bias -= slope*(w-ts)` floored at 0; permanent locks return constant `permanent`. |
| `getPastTotalSupply(w)` | `getAdjustedGlobalVotes` (L461) → `_getAdjustedCheckpoint` (L475) | last global checkpoint ≤ w, walks weekly applying `globalSlopeChanges`, returns `bias+permanent`. |
| `getFirstEscrowPoint(id)` | `firstCheckpoint()` (L565) | first-ever checkpoint of the NFT → first claimable week. |
| `getPastEscrowPoint(id,now)` | `getAdjustedEscrow` (L420) | `maxTs==0` ⇒ token never existed ⇒ `_claim` returns 0. |
| `supply()` | storage | total locked; used only by `calculate_rebase` split math. |

**Key composition property (INFERRED, standard Velodrome/ApeGuru "EscrowDelegate" design):** both per-NFT bias and global votes are decayed from the *same* slope data (`_escrowCheckpoints[id].slope` aggregated into the global slope and scheduled into `globalSlopeChanges[endTime]` by `checkpoint()`), so `Σ_id balanceOfNFTAt(id,w) == getPastTotalSupply(w)` up to floor rounding. On-chain corroboration (READ): `token_last_balance = 799,028.3222 HYDX` equals the live `balanceOf(RDIST)` exactly, and `VE.supply()`/`totalSupply()` are consistent — no desync has accumulated in production.

**Why the flagged boundary manipulation (deposit huge → cross week → claim → withdraw) fails:** both reads are at *past, week-aligned* `w < last_token_time`. `upperLookupRecent(w)` on a lock created after `w` returns "not found" ⇒ balance 0 ⇒ **history cannot be back-filled**. To hold non-zero `balanceOfNFTAt(id,w)` you must have locked *before* `w`; and voting power ≈ amount only when remaining duration ≈ `MAX_TIME` (2y), which for a non-permanent lock cannot be withdrawn until expiry, and for a permanent lock requires `unlockRolling` + cooldown. There is no flash/temporary path — any share captured is the attacker's genuine time-weighted stake, and total rebase is capped at ≤26% of weekly. Not disproportionate.

### Minter write ordering (reentrancy / double-mint)
`update_period` (L339): `nonReentrant` wraps the whole body; `active_period = current_period` is written (L342) **before** any external `mint/transfer/notify`, and `can_update_period()` (L319) requires `block.timestamp ≥ active_period + WEEK`. Re-entry or a second same-week call finds the guard false ⇒ no mint. Catch-up over missed weeks sets `active_period` to *this* week (not `+= WEEK`) and mints exactly one `weekly` ⇒ under-mints, never over. (READ)

### RDIST claim ordering (reentrancy)
`_claim` writes `time_cursor_of[tokenId]` (L181) **before** `_distributeRewards` does the external VE call, so re-claiming the same token in a callback yields 0. Any reentrant *state-changing* claim is additionally blocked because `VotingEscrowV2Upgradeable.increaseAmount/createLockFor` are `nonReentrant` and the outer distribution is already inside a VE call. `token_last_balance -= amount` after the call is safe (guard already advanced). (READ/INFERRED)

---

## 3. Findings

### 3-A (SAFE, documented) — `update_period` cannot be driven to over-mint or mis-split
`weekly = totalSupply_or_initialSupply * rate/1e18`, `rate` bounded (≤1.2% bootstrap, ≤2% tail). `rebase = weekly * min(lockedShare, 26%…)`, `team = weekly*teamRate/1000 (≤5%)`, `gauge = weekly - rebase - team` (checked-math; `rebase+team ≤ 31% < 100%` ⇒ no underflow-revert DoS either). HYDX `mint()` is owner-gated to the Minter, so `totalSupply` cannot be inflated by an attacker; `useInitialSupply=1` fixes the base at 500M regardless. Inflating `ve.supply()` before the call only shifts gauge→rebase within the 26% cap (no extra mint) and the rebase is still distributed time-weighted. **No over-mint.**

### 3-B (Low / correctness — fund strand) — `_claim` uses `continue` without advancing `week_cursor`
`RewardsDistributorV2.sol:168-181`
```solidity
for (uint i = 0; i < 50; i++) {
    if (week_cursor >= _last_token_time) break;
    uint256 balance_of = IVotingEscrowV2(ve).balanceOfNFTAt(_tokenId, week_cursor);
    if (balance_of == 0) continue;      // L172  <-- does NOT do week_cursor += WEEK
    if (balance_of != 0) { to_distribute += balance_of * tokens_per_week[week_cursor]
                                          / IVotingEscrowV2(ve).getPastTotalSupply(week_cursor); }
    week_cursor += WEEK;                // L178  reached only on the non-zero path
}
time_cursor_of[_tokenId] = week_cursor; // L181
```
The view twin `_claimable` uses `break` on the same condition (`RewardsDistributorV2.sol:215`), and canonical Curve/Solidly `ve_dist` unconditionally does `week_cursor += WEEK`. Here, a token whose claimable range contains an **interior zero-balance week** spins on that week for all 50 iterations and persists `time_cursor_of` at it; every future `claim` repeats ⇒ all rebase from that week onward is **permanently stranded**.

- Reachability: a non-permanent lock that is allowed to fully expire (bias→0 for ≥1 week) and is later re-activated via `increaseUnlockTime`/`increaseAmount` produces `>0, 0, >0` across weeks. Healthy permanent locks (constant `permanent`) and never-lapsed non-permanent locks (monotone decay to 0 then stays 0) never hit an interior zero, so **an attacker cannot induce this on a third party's healthy lock**.
- Trace: weeks `W0>0, W1>0, W2=0, W3>0`. i0→W0 (cursor W1), i1→W1 (cursor W2), i2..i49→W2 `continue` (cursor stuck W2). `time_cursor_of=W2` forever ⇒ `W3+` lost.
- Impact: user fund loss (griefable only by the owner's own action), **not** attacker profit; `to_distribute` is only ever added on the non-zero branch which always advances, so it can never double-count or over-pay. Severity Low.
- Fix: advance unconditionally — replace `if (balance_of == 0) continue;` with `if (balance_of == 0) { week_cursor += WEEK; continue; }` (and align `_claimable` to match).

### 3-C (Info / griefing) — `claim` / `claimInto` / `claimManyInto` lack caller authorization
`claim` (L315) performs no `ownerOf`/approval check on `_tokenId`. Confirmed by simulation: `claim(1)` from `0xdEaD` succeeds and returns ~28,979e18, but `_distributeRewards` routes it to `ownerOf(1)=0xd9e9…` via `increaseAmount`/`createLockFor(...,tokenOwner,PERMANENT)` (L358-375) — **never to `msg.sender`**, so there is no theft. The only effect an attacker gets is *forcing* a locker's pending rebase to be realized into a permanent lock at a time of the attacker's choosing (mild griefing / gas). `claimInto`/`claimManyInto` additionally `require` equal owners, so cross-owner redirection is impossible.
- Fix (optional hardening): gate on `isApprovedOrOwner(msg.sender,_tokenId)` (or the VE claim-redirect approval) if forced claims are undesirable.

### 3-D (SAFE, documented) — `checkpoint_total_supply` public call is value-neutral
Anyone may call it (L138), but it only calls `ve.checkpoint()` and, if `block.timestamp≥time_cursor`, sets `time_cursor = timestamp()+WEEK`. It cannot mutate any *historical* `getPastTotalSupply(w)`/`balanceOfNFTAt(id,w)` (those re-derive from immutable past checkpoints), and `last_token_time` (the claim cutoff) is written only inside the depositor-gated `_checkpoint_token`. No distribution shift.

---

## 4. Out-of-scope centralization notes (privileged; not exploitable by an unprivileged attacker)
- **`RewardsDistributorV2.withdrawERC20(address)`** (L401): `owner` (`0x1ae3…0311`) can transfer the entire 799K HYDX out at will. Full rug of the reserve rests on that key.
- **`MinterUpgradeableV4._initialize(...)`** (L266): the single-use guard is `require(_initializer != address(0))`, but success sets `_initializer = address(1)` (`_INITIALIZED_ADDRESS`), which is still `!= address(0)`. Therefore `governor` (`0xdf52…898f`) can call `_initialize` again with `max>0` and mint arbitrary HYDX into locks it controls. Recommend either burning the flag (`_initializer = address(0)`) at the end of `_initialize`, or gating it behind the OZ initializer machinery. Verify `governor` is a Timelock/multisig.
- Minter `governor`/`teamAdmin`/`owner`, RDIST `owner`, Schedule `governance` should all be timelocks/multisigs (they currently resolve to two distinct privileged contracts, `0xdf52…` and `0x1ae3…`).

## Rejected candidates (killed)
- **Initializer/reinitializer front-run** — `_initialized=2` on-chain; `initialize` and `reinitializeV4` both revert. Dead.
- **VE `balanceOfNFTAt` vs `getPastTotalSupply` desync / boundary "deposit-cross-withdraw"** — past week-aligned reads are immutable and back-fill-proof; capturing share requires genuine long-duration locked stake; both derived from the same slope data; on-chain `token_last_balance == balanceOf` shows no live desync.
- **Rounding drift over many epochs/tokenIds** — every share division floors down ⇒ `Σ claims ≤ Σ tokens_per_week`; dust is stranded in-contract, never over-paid. `balance*tokens_per_week ≈ 1e51 << 2^256` ⇒ no overflow.
- **Reentrancy double-claim in `claim`/`update_period`** — `time_cursor_of` / `active_period` written before external calls; VE claim path is `nonReentrant`; Minter `update_period` is `nonReentrant`.
- **Double-mint via missed-week catch-up** — `active_period` jumps to current week and mints exactly one `weekly` (under-mints).
- **`checkpoint_token` abuse** — `assert(msg.sender==depositor)`; depositor=Minter.
