# State-dependency & composition map — Hydrex (HYDX)

This is the second required artifact: for the value/power-bearing functions, **what state each writes and
which other functions read that state and trust it**, then the **compositions** worked (call A to move
state, call B to harvest; flash-loans; epoch boundaries; reentrancy; rounding drift). Intra-subsystem
detail lives in the per-subsystem files (`subsystem-*.md`); this file is the **cross-contract synthesis**
plus the structural argument for why most compositions can't yield a disproportionate gain.

Snapshot 2026-08-16, Base. READ = confirmed from source/live; INFERRED = deduced.

## The structural fact that shapes every composition

Almost every value flow in this system is **proportional to a stake the attacker must actually hold**:
- ve rebase (`RewardsDistributorV2`) pays `tokens_per_week · balanceOfNFTAt(id,week) / getPastTotalSupply(week)` — proportional to your ve balance during the week.
- Bribes/fees (`BribeV2`) pay proportional to your vote weight during the epoch.
- Emissions (`Minter → Voter`) flow to gauges proportional to votes.
- oHYDX exercise gives you HYDX only in exchange for oHYDX you hold (1:1 backed), priced at `max(floor, 30%·TWAP)`.

So a **flash-loan / one-block** manipulation that doesn't leave the attacker holding the stake across the
measured window earns nothing, and a manipulation that *does* require holding the stake earns in proportion
to it — failing the "disproportionate, stake-independent" economic bar. A real **economic** finding therefore
has to be an **accounting bug that breaks proportionality** (a checkpoint desync, a double-count, a rounding
drift that compounds, an epoch-boundary that credits weight you didn't hold). A real **unauthorized-access**
finding has to be a **missing/defeatable guard** on a fund- or privilege-moving function. The two artifacts
(entry-point enumeration + this map) are structured to hunt exactly those two things across the whole surface,
not to re-derive that stake-proportional flows are safe.

## Cross-contract dependency edges (reader trusts writer)

| # | Reader (function) | State it trusts | Writer of that state | Can an unprivileged attacker move the writer before the reader? | Verdict |
|---|---|---|---|---|---|
| 1 | `OptionTokenV4.exercise/_exercise` → `getMinPrice` | pool tick-cumulative TWAP over 7200s | every `swap` on `AlgebraPool 0x51f0` (writes oracle timepoints) | Yes on spot; the 2h TWAP resists single-tx moves and **the floor backstops it** | **Bounded (verified).** Live: `getMinPrice(1000 HYDX)=10.0 USDC = max(floor 10.0, 30%·TWAP 4.56)`. Floor `0.01 USDC/HYDX` ≈ market ⇒ pushing TWAP→0 still pays the floor. Decimals (18/6) scale correctly. No cheap-exercise. |
| 2 | `OptionTokenV4.getMinPrice` | `feeDistributor.floorPrice()` | `SimpleFloorGuardian` (privileged) | No — privileged writer | Out of scope (privileged); but the floor is the whole backstop for #1, so its live value was verified. |
| 3 | `RewardsDistributorV2._claim` | `ve.balanceOfNFTAt(id,wk)`, `ve.getPastTotalSupply(wk)` | ve lock ops (`createLock`/`increaseAmount`/`merge`/`split`) — **historical/checkpointed** | Only your *own* balance, and only going forward (can't rewrite a past week) | **Stake-proportional + reward goes to the NFT owner, not the caller** (`_distributeRewards`→`increaseAmount`/`createLockFor(ownerOf(id))`). Missing ownership guard on `claim` ⇒ griefing at most, not theft. Checkpoint math scrutinized in `subsystem-mint.md`. |
| 4 | `BribeV2.getReward/earned` | vote-weight checkpoints `balanceOfAt`, `supplyCheckpoints` | `Voter.vote/reset/poke` → `Bribe._deposit/_withdraw` (Voter-only) | Only your own vote, set through the Voter | Epoch-boundary double-count / claim-after-withdraw is the classic risk → worked in `subsystem-incentives.md`/`subsystem-voter.md`. |
| 5 | `Minter.update_period` | `emissionSchedule.calculateWeeklyEmission`, `token.totalSupply`, `ve.supply`, `active_period` | schedule (pure), token, ve — all honest/checkpointed; `active_period` self | Caller can't bias inputs; `can_update_period` gates one mint/period; `nonReentrant` | **Bounded** (verified in `subsystem-mint.md`): permissionless call mints only the schedule to protocol contracts, nothing to caller. |
| 6 | `Voter.distribute` (emissions to gauge) | gauge vote weights | `Voter.vote` ← ve balance | Only your own votes | Capital-proportional; accounting checked in `subsystem-voter.md`. |
| 7 | pool 100% community fee → `GaugeIncentiveCampaign._claimFees` → `BribeV2` | swept fee balances | pool swaps (fees), `_claimFees` sweep | Anyone can generate fees by swapping (pays them); sweep routes to bribe | Fees captured by voters proportional to vote weight; routing guard + `_claimFees` reachability checked in `subsystem-incentives.md`. |
| 8 | `OptionFeeDistributor.distribute` | called with (amount, payment) by oToken | `OptionTokenV4._exercise` | Only via a real exercise (attacker pays) | Guard = onlyOToken (checked in `subsystem-options.md`). |

## Compositions explicitly worked at the cross-contract level

- **Flash-loan the pool → cheap oHYDX exercise (edge 1).** Rejected: the exercise price is `max(floor, 30%·TWAP_2h)`; the floor (live 0.01 USDC/HYDX ≈ market) binds and is independent of the flashed price, and the 2h TWAP can't be moved to a sustained low by a single-tx flash loan. Numeric: to exercise below the floor you'd need `floorPriceAmount < discountedAmount` false to not matter — but `getMinPrice` returns the max, so floor is a hard lower bound. No profit. (Verified live.)
- **Inflate ve balance at the rebase checkpoint → over-claim rebase (edges 3).** Rejected: reward is `balance/totalSupply` over weeks you actually held the lock (checkpointed history), reward is credited to the NFT owner's lock (not liquid to the attacker unless they already own a withdrawable position), and the share scales with the capital locked. Not stake-independent. Residual accounting-bug check delegated to `subsystem-mint.md`.
- **Vote at epoch boundary → claim a full epoch of bribes/fees for weight briefly held (edge 4).** This is the one genuinely dangerous class (classic Solidly bribe bug). Worked in `subsystem-incentives.md` + `subsystem-voter.md` — see those for the checkpoint-index arithmetic and verdict.
- **Trigger the Voter's delegatecall modules to corrupt Voter storage (edges 4/6).** Storage-layout equivalence of `gaugeLogic`/`claimLogic` vs `VoterV5_Storage` checked in `subsystem-voter.md`.
- **oHYDX `exerciseVe` for free (edge 1 variant).** Rejected: burns oHYDX (1:1 HYDX-backed) to create a permanent veHYDX lock of equal size — a fair 1:1 conversion, no free value; you gave up an asset worth ~1 HYDX to lock 1 HYDX.

## Per-subsystem detail
Full entry-point guard tables and intra-subsystem compositions:
`subsystem-options.md` · `subsystem-ve.md` · `subsystem-voter.md` · `subsystem-mint.md` · `subsystem-incentives.md`.
Surviving findings (if any) are consolidated in `FINDINGS.md`.
