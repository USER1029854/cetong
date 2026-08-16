# Live authority map — who holds power over HYDX right now

Snapshot date: 2026-08-16 (Base mainnet, chainid 8453). All values read live on-chain
(`getOwners`/`getThreshold`, `getRoleMember*`, `owner()`, EIP-1967 slots). Raw data:
[`authorities.json`](./authorities.json), [`holdings.json`](./holdings.json).

> The HYDX token's own code trusts one address completely: `owner()`, which can mint with no
> cap or rate-limit. Everything below is the system that address is wired into. **Nothing about
> HYDX's security is decided by HYDX's own code beyond "the owner is honest and uncompromised."**

## The two human key sets

Four EOAs sign for everything through a set of Gnosis Safes:

| EOA | Admin Safe `0x1ae3…0311` (2/4) | Treasury Safe `0xd9e9…50af` (2/3) | Floor Safe `0x704e…b476` (2/3) | Proposer Safe `0x7695…5f4a` (3/3) |
|---|:--:|:--:|:--:|:--:|
| `0x35e8153614c26f31b78e661184d19d3c25702d67` | ✔ | | | |
| `0xea1bf482b7d3526ccf37a8a3fee330c960877f08` | ✔ | ✔ | ✔ | |
| `0x813f98f0f29509d558b2479d8ee0c8068c160bd3` | ✔ | ✔ | ✔ | ✔ |
| `0xb4d2861d525aef313be0c497c3335a58f637e73e` | ✔ | ✔ | ✔ | ✔ |
| `0x74266f2b206d1359b83fc74949ef07176fb3ae03` (also AlgebraFactory owner) | | | | ✔ |

All five are plain EOAs (some carry EIP-7702 delegations to a shared smart-account impl
`0x63c0c19a…`, but that does not change signer semantics). `0x813f98f0` and `0xb4d2861d`
appear in **all four** Safes — compromise of those two keys is close to protocol-wide.

## Powers over the target, by holder

### Admin Safe `0x1ae3753d9b60743a89159ccff8e251c60b560311` — Safe v1.4.1, **2-of-4**, nonce 567
The single most powerful standing key set. Holds, right now:
- **`owner()` of the Minter** — gates `setInitialSupply` (rebase base). (Mint rate itself is schedule-bound; see below.)
- **`DEFAULT_ADMIN_ROLE` + `ADMIN_ROLE` + `PAUSER_ROLE` on OptionTokenV4 (oHYDX)** — can `setDiscount`,
  `setPaymentConfiguration` (swap the TWAP oracle / pair), `setFeeDistributor`, `setTwapSeconds`,
  `toggleExternalOption`, `burn`. **This tunes the price at which the 31.06M HYDX (30.4% of supply) held
  in oHYDX is released.** See `../contracts/options/OptionTokenV4_*`.
- **`owner()` of RewardsDistributorV2** — `withdrawERC20` lets it sweep the distributor's HYDX
  (currently 799K HYDX) to itself. (`RewardsDistributorV2.sol:401`, `require(msg.sender == owner)`.)
- **`VOTER_ADMIN`, `GAUGE_ADMIN`, `CL_FEES_VAULT_ADMIN` on the Voter PermissionsRegistry `0x3ea4…`** —
  can set the Voter's delegatecall logic (`gaugeLogic`/`claimLogic`), i.e. arbitrary code in the
  Voter's storage context.
- **`EXECUTOR_ROLE` on the Timelock** — the address that executes upgrades after the 24h delay.
- **`owner()` of** EmissionSchedule (governance), IncentiveCampaignManager, SimpleFloorGuardian,
  PoolEligibilityOracle, GaugeFactoryIncentiveCampaign, and most peripheral contracts.

### Timelock `0xdf52b5a03e3f5a4178e4f63e8bc51abe691b898f` — `TimelockControllerEnumerable`, **minDelay = 86400s (24h)**
- `PROPOSER_ROLE` + `CANCELLER_ROLE` = **Proposer Safe `0x76954c21…` (3-of-3)**.
- `EXECUTOR_ROLE` = Admin Safe `0x1ae3…`.
- **`owner()` of the shared ProxyAdmin `0x6e25d241a3ba9e0278a296b398e9678e5ed8ad40`** → can upgrade
  the implementations of the **Minter, Voter, VotingEscrow, OptionFeeDistributor, VeArtProxy,
  BribeFactory, floorGuardian, MevX components, campaign manager, CUSTOM_POOL_DEPLOYER,
  PoolEligibilityOracle** (every EIP-1967 proxy whose admin is `0x6e25…`).
- Also the Minter's `governor` and `teamAdmin` → can `setEmissionSchedule` (swap the mint-bound
  contract), `setTeamRate`, `setVoter`, `setRewardDistributor`, `setEmissionsGovernor`.
- Voter PermissionsRegistry `GOVERNANCE` + `INFRA_ADMIN`.

**Upgrade path to arbitrary HYDX mint:** Proposer Safe (3/3) schedules → wait 24h → Admin Safe (2/4)
executes → new Minter impl (or new EmissionSchedule) can mint without the 2% cap. This is the only
route to unbounded mint; it is timelocked and multi-sig gated, not a single key.

### AlgebraFactory owner — bare EOA `0x74266f2b206d1359b83fc74949ef07176fb3ae03`
Single-key control of the DEX factory (`AlgebraFactory.owner()` and its `DEFAULT_ADMIN_ROLE`). Also
holds `GAUGE_ADMIN`/`BRIBE_ADMIN` on the Voter registry and `GOVERNANCE`/`GAUGE_ADMIN` on the
feeDistributor registry, and is a signer on the 3-of-3 Proposer Safe. What this key can do to the
**existing** $460K pool (change plugin/community-fee/etc.) is analyzed in
[`liquidity-analysis.md`](./liquidity-analysis.md). `defaultCommunityFee` is currently 0.

### Plugin / vault upgrade authority
- Main-pool **plugin logic** is a beacon proxy; the beacon `0x106937fc…` is owned by the
  **pluginFactory `0xa8dd4c05…`** — whoever controls the pluginFactory can swap the live hook logic
  on the pool (and thereby the volatility-oracle feed used for oHYDX pricing). Exact pluginFactory
  controller: see liquidity analysis.
- **communityVault / gauge logic** beacon `0x799b61d7…` is owned by `BeaconFactoryAdmin 0xdb5a8524…`.

### Emergency
- Voter emergency council = **`PauseGuardian 0xcf57aa5b…`**. OptionToken `PAUSER` = Admin Safe.
- AlgebraFactory `POOLS_ADMINISTRATOR` = `AlgebraCustomPoolEntryPoint 0x00ede53f…` and a vanity EOA
  `0xdead1f5af792afc125812e875a891b038f888258` (EIP-7702 delegated).

## Mint bound (why "unlimited mint" is qualified)
HYDX `mint()`/`initialMint()` are `onlyOwner` = Minter. The Minter exposes **no arbitrary mint** to
its own governor/team: the only live mint path is `update_period()` (permissionless to call, mints
only `emissionSchedule.calculateWeeklyEmission`). `RevisedPhasedEmissionSchedule` caps the weekly
rate at **≤ 2% of totalSupply** (tail), adjustable only ±0.02%/epoch by its governance (Admin Safe).
`_initialize()` (one-time genesis mint) is already consumed (`initialMinted = true`,
`_initializer == address(1)`). So absent a timelocked upgrade or schedule swap, per-week mint is
bounded by code. The bound is not immutable — it rests on the Timelock + Admin Safe not replacing
the schedule or the Minter impl.
