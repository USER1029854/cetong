# Off-chain components in the HYDX trust path

Contracts can be read and simulated; the decisions below are made by humans or servers with no
bytecode. Each is named with the on-chain address it authenticates as, what it decides, what breaks
if it decides wrongly or is compromised, and whatever on-chain evidence bounds its real behavior.

## 1. Gauge-eligibility oracle updater — EOA `0x40fbfe5312330f278824ddbb7521ab77409192f0`
- **On-chain anchor:** `PoolEligibilityOracle` (proxy `0xc98fb7b5…`, impl `0x0d3d15a7…`)
  `oracleUpdater` slot = this EOA. Guard: `setPoolEligibility` requires `msg.sender == oracleUpdater
  || owner()` (`PoolEligibilityOracle.sol:55`).
- **What it decides:** which pools return `canCreateGauge == true`, i.e. which pools may get an
  INCENTIVE_CAMPAIGN gauge created **permissionlessly** (`VoterV5_GaugeLogic.sol:247`). `GAUGE_ADMIN`
  (Admin Safe / factory EOA) can create gauges for any pool regardless, bypassing this.
- **If wrong/compromised:** it could mark an illegitimate pool eligible, letting anyone spin up a
  gauge that then receives voter-directed HYDX emissions/incentives — a misdirection/dilution of
  emissions, **not** a mint beyond schedule and **not** a drain of the main pool. Bounded impact.
- **Evidence of real behavior (Blockscout, Base):** this EOA has called `setPoolEligibility`
  **13 times, all successful**, from 2026-01-20 through 2026-06-10. It is an active, recurring
  off-chain job, not a dormant switch. It is the same EOA that deployed HYDX (`creator_address`) and
  it carries an EIP-7702 delegation to shared smart-account impl `0x63c0c19a…`. `owner()` of the
  oracle is the Admin Safe, which can replace the updater.

## 2. ALM (automated liquidity management) rebalance keeper
- The main $460K pool's plugin (`AlgebraUpgradeablePlugin`, impl `0xaf11628e…`) bundles an ALM module
  whose rebalancing is driven by an **off-chain keeper/operator** submitting rebalance transactions.
  The on-chain address it authenticates as, what it can move, and the guardrails are detailed in
  [`liquidity-analysis.md`](./liquidity-analysis.md). An ALM keeper that rebalances adversarially or
  at manipulated prices can move the pool's managed liquidity to the LPs' disadvantage; it does not
  hold HYDX mint rights. This is also why the pool's on-chain reserves (21.55M HYDX / 229.9K USDC now
  vs the ~$559K reserve quoted at discovery) shift over time — the ALM re-ranges the position.

## 3. MEV capture keeper (MevX)
- The plugin also wires an MEV subsystem (`MevxExecutor`, `MevxRouter`, `ProfitDistributor`,
  `SecurityRegistry`). The executor/router implementations are **unverified** — see
  [`../recovered/`](../recovered/) for recovered behavior — and are driven by an off-chain MEV
  operator. On-chain authenticating addresses and reachability from the pool are in
  [`liquidity-analysis.md`](./liquidity-analysis.md). `ProfitDistributor.owner` is a vanity EOA
  `0x000000077ac13a2fc7c7a154d28e6251a5e4648b` (EIP-7702 delegated).

## 4. Multisig signer key custody (the ultimate off-chain trust)
Every privileged action ultimately routes to a handful of EOAs signing Gnosis Safes
(see [`AUTHORITIES.md`](./AUTHORITIES.md)). The security of HYDX's mint, the oHYDX cheap-sell
parameters, and all proxy upgrades reduce to the off-chain custody of keys `0x813f98f0…`,
`0xb4d2861d…`, `0xea1bf482…`, `0x35e81536…`, and `0x74266f2b…`. Threshold is 2-of-4 (Admin Safe) for
most actions and 3-of-3 (Proposer Safe) to schedule an upgrade. There is no on-chain way to bound
whether these keys are held by distinct, honest parties on distinct hardware — that is an assumption.

## 5. Emissions governor signal — currently INACTIVE
`Minter.emissionsGovernor == address(0)`. The Minter's `update_period()` will `try` to call
`tryExecuteSignal()` on an emissions-governor (an off-chain-vote-driven emission adjuster) but the
slot is unset, so no such component is live today. If set later it would become an off-chain input to
emissions; record it as a watch item.

## Not off-chain (worth stating explicitly)
- **oHYDX exercise pricing is on-chain.** `AlgebraIntegralTwap.estimateAmountOut` reads the pool
  plugin's on-chain tick TWAP (`getTimepoints`, `AlgebraIntegralTwap.sol:45`); there is no operator
  price feed. Manipulation requires moving the pool TWAP over the 2h window, backstopped by
  `SimpleFloorGuardian.floorPrice`. (Caveat: the TWAP is sourced from the *plugin's* volatility
  oracle, and the plugin logic is upgradeable via its beacon — so plugin-upgrade authority indirectly
  reaches oHYDX pricing.)
- **The Hydrex perpetuals engine is not in HYDX's on-chain authority graph.** No perp/clearing/margin/
  settlement contract holds a role over the HYDX token, the Minter, the pools, or any registry (scanned;
  none found). If a perp system exists it uses HYDX only as a traded/collateral asset, not as an
  authority over it. An auditor expecting the "perp" half of "DEX/perp" will not find it wired to this
  token; it is a separate deployment out of this graph's scope.
