# Entry-point enumeration — Hydrex (HYDX) bespoke in-scope surface

First required artifact: **every externally-reachable, state-changing entry point** across the bespoke
in-scope contracts, built mechanically from ABIs (impl ABI for proxied logic) **before** any triage, then
each accounted for with its guard and a one-line reason it isn't exploitable (or a note that it is). The
raw machine output is [`ENTRY_POINTS_raw.md`](./ENTRY_POINTS_raw.md) (regenerable via `enum_entrypoints.py`);
the per-function guard tables live in the linked per-subsystem files. This page is the master index and the
completeness ledger.

**Total: 284 state-changing external/public entry points across 24 bespoke contracts — every one accounted
for** in the linked tables below. (View/pure getters and the pure ERC20/ERC721 metadata surface are not
value-changing and are covered implicitly; fallback/receive: none of the bespoke contracts define a
payable fallback/receive — verified by source scan in `enum_entrypoints.py`.)

## Coverage ledger

| Contract | Callable at | State-changing EPs | Guard pattern (summary) | Detailed table |
|---|---|---:|---|---|
| HydrexToken (target) | `0x00000e7e` | 10 | OZ ERC20 + `onlyOwner` mint | [unassigned-contracts-guards.md](./unassigned-contracts-guards.md) |
| MinterUpgradeableV4 | `0xa7d6` (proxy) | 19 | `governor`/`teamAdmin`/`onlyOwner`; `update_period` permissionless but value-neutral | [subsystem-mint.md](./subsystem-mint.md) |
| RevisedPhasedEmissionSchedule | `0x5aaa` | 2 | `onlyGovernance`; pure math ≤2% cap | [subsystem-mint.md](./subsystem-mint.md) |
| RewardsDistributorV2 | `0x6fca` | 9 | `owner`/`depositor`; `claim*` permissionless but pays NFT owner | [subsystem-mint.md](./subsystem-mint.md) |
| OptionTokenV4 (oHYDX) | `0xa113` | 22 | AccessControl (`ADMIN`/`MINTER`/`PAUSER`); exercise* bounded 1:1 by caller oHYDX | [subsystem-options.md](./subsystem-options.md) |
| OptionFeeDistributor | `0xdb2f` (proxy) | 7 | onlyOToken / pulls from caller | [subsystem-options.md](./subsystem-options.md) |
| SimpleFloorGuardian | `0xa007` (proxy) | 5 | `onlyOwner`/registry; `deposit` pulls from caller | [subsystem-options.md](./subsystem-options.md) |
| AlgebraIntegralTwap | `0xf524` | 0 | view-only oracle | [subsystem-options.md](./subsystem-options.md) |
| VotingEscrowV2Upgradeable | `0x25b2` (proxy) | 29 | `checkAuthorized`/`ownerOf`; lock invariants hold | [subsystem-ve.md](./subsystem-ve.md) |
| ↳ LockLogic / ApprovalLogic | `0x5c8d` / `0x4b0b` | (delegatecall) | reachable only via the ve proxy (counted in the 29); direct calls hit empty storage | [subsystem-ve.md](./subsystem-ve.md) |
| VoterV5 | `0xc69e` (proxy) | 43 | PermissionsRegistry roles; vote/reset/poke self-scoped; `notifyRewardAmount` minter-only | [subsystem-voter.md](./subsystem-voter.md) |
| VoterV5_GaugeLogic | `0x8cf7` (delegatecall) | 1 | runs in Voter storage (aligned) | [subsystem-voter.md](./subsystem-voter.md) |
| VoterV5_ClaimLogic | `0x68ed` (delegatecall) | 13 | claims gate on VE approval, pay owner | [subsystem-voter.md](./subsystem-voter.md) |
| PermissionsRegistry ×2 | `0x3ea4` / `0x4180` | 8 + 8 | `onlyAdminMultisig`; no self-grant | [subsystem-voter.md](./subsystem-voter.md) |
| GaugeIncentiveCampaign | `0xac39` (proxy) | 16 | `onlyDistribution`(Voter)/registry; staking stubbed | [subsystem-incentives.md](./subsystem-incentives.md) |
| IncentiveCampaignManager | `0x416d` (proxy) | 14 | `owner`/registry | [subsystem-incentives.md](./subsystem-incentives.md) |
| GaugeFactoryIncentiveCampaign | `0xbe50` (proxy) | 14 | mostly `onlyAllowed` — **`createGaugeV2` UNGUARDED (F-1)** | [subsystem-incentives.md](./subsystem-incentives.md) |
| BribeV2 | `0xb69b` / `0x3fde` | 17 | `deposit/withdraw` Voter-only; `getReward` owner/approved | [subsystem-incentives.md](./subsystem-incentives.md) |
| BribeFactoryV4 | `0x58b4` (proxy) | 18 | role-gated | [subsystem-incentives.md](./subsystem-incentives.md) |
| Pair (Solidly HYDX/USDC) | `0x605abd` | 11 | AMM math; `_k` enforced pre-check; `lock` reentrancy guard | [subsystem-incentives.md](./subsystem-incentives.md) |
| PairFees | `0xada5` | 1 | `onlyPair` | [subsystem-incentives.md](./subsystem-incentives.md) |
| PoolEligibilityOracle | `0xc98f` (proxy) | 7 | `oracleUpdater`/`onlyOwner` | [unassigned-contracts-guards.md](./unassigned-contracts-guards.md) |
| VeArtProxy | `0x7cba` (proxy) | 3 | `onlyOwner`/initializer; art only | [unassigned-contracts-guards.md](./unassigned-contracts-guards.md) |
| AlgebraCustomPoolEntryPoint | `0x00ede` | 7 | `onlyCustomDeployer(pool)` — cannot touch the main pool | [unassigned-contracts-guards.md](./unassigned-contracts-guards.md) |

**The only entry point flagged as exploitable is `createGaugeV2` (F-1, LOW, bounded to spam — reaches no
funds/control).** Every other one of the 284 resolves to: a role/owner/registry gate that reverts for an
unprivileged caller (verified live from `0xdEaD` for the highest-value ones), a pull-from-caller transfer
that cannot move protocol funds, or a value-releasing path bounded 1:1 by the caller's own stake. Full
per-function detail and the "why-safe" one-liners are in the linked subsystem tables.

## Upstream / infra surface (excluded from bespoke bug-hunt, rationale in `FINDINGS.md` §Scope)
Algebra pool/factory/plugin (pool core byte-identical to v1.2.1), OZ, Gnosis Safe, Timelock/ProxyAdmin,
USDC. Their admin surfaces are privileged (out of the unprivileged-attacker model); the "no principal-drain"
analysis of the pool/plugin is in [`../live-state/liquidity-analysis.md`](../live-state/liquidity-analysis.md).
