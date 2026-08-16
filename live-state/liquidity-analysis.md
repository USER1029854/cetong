# Hydrex (HYDX) Liquidity Subsystem — Behavioral Authority Map

Scope: the main HYDX/USDC concentrated-liquidity pool holding ~$559K and its trust path
(plugin/hook, community-fee vault, security switch, MEV keepers). Base (chainid 8453).
Date of live reads: 2026-08-16. Method: verified source (READ) vs. `eth_call`/storage (LIVE)
vs. reasoning (INFERRED). No exploit is asserted; this is a control-surface map.

Key contracts (LIVE-confirmed):
- Pool `0x51f0b932855986b0e621c9d4db6eee1f4644d3d2` — token0=HYDX (`0x00000e7e…`, 18d), token1=USDC (`0x833589fc…`, 6d). Verified `factory.poolByPair(HYDX,USDC)==pool` → it is a **default** pool (not custom).
- Plugin proxy (hook) `0xe33a242990780ab872ae986ad68206478fc85ae1` (AlgebraPluginProxy → beacon `0x106937fc…` → impl `0xaf11628e…` AlgebraUpgradeablePlugin).
- Factory `0x36077d39cdc65e1e3fb65810430e5b2c4d5fa29e`.
- Community vault / gauge `0xac396cabf5832a49483b78225d902c0999829993` (BeaconProxy → beacon `0x799b61d7…` → impl `0x22d23d13…` GaugeIncentiveCampaign).
- Security registry `0x4cb52ea0096606e7843754936944a860e6f12cb6`.

LIVE pool state (`globalState`, `getReserves`): reserve0 = 21,548,011.53 HYDX; reserve1 = 229,900.91 USDC (pool token balances == reserves, i.e. **nothing skimmable**). communityFee = **1000 = 100%**; stored lastFee = 500 (0.05%); dynamic `fee()` currently = 10000 (1%); pluginConfig = **215**; tickSpacing = 60; unlocked = true; pluginFeePending = 0; communityFeePending ≈ small (≈ a few HYDX + 0.016 USDC).

pluginConfig 215 = `BEFORE_SWAP | AFTER_SWAP | BEFORE_POSITION_MODIFY | BEFORE_FLASH | AFTER_INIT | DYNAMIC_FEE` (absent: AFTER_POSITION_MODIFY, AFTER_FLASH). Flag values: `AlgebraPool_0x51f0d3d2/contracts/libraries/Plugins.sol:19-26`.

---

## 1. Pool admin / permission surface (function → gate → LIVE authority)

Source: `AlgebraPool_0x51f0d3d2/contracts/AlgebraPool.sol`. All admin setters call
`_checkIfAdministrator()` (line 472-474) = `IAlgebraFactory(factory).hasRoleOrOwner(POOLS_ADMINISTRATOR_ROLE, msg.sender)`.
`hasRoleOrOwner` = `owner()==account || hasRole(role,account)` (`AlgebraFactory.sol:78-80`), so the **factory owner passes every role check**.

| Pool function | Line | Gate (READ) | LIVE authorities who can call |
|---|---|---|---|
| `setCommunityFee(uint16)` | 479 | factory owner or POOLS_ADMINISTRATOR; ≤ MAX=1000 | `0x74266f2b` (owner), `0xdead1f5a`, `0x00ede53f` * |
| `setTickSpacing(int24)` | 490 | owner or POOLS_ADMINISTRATOR | same |
| `setPlugin(address)` | 497 | owner or POOLS_ADMINISTRATOR — **swaps the live hook** (zeroes pluginConfig then sets new plugin) | same |
| `setPluginConfig(uint8)` | 504 | the plugin **or** owner/POOLS_ADMINISTRATOR | plugin `0xe33a2429`, `0x74266f2b`, `0xdead1f5a`, `0x00ede53f` * |
| `setCommunityVault(address)` | 514 | factory (initial) or owner/POOLS_ADMINISTRATOR — **redirects where 100% of fees go** | `0x74266f2b`, `0xdead1f5a`, `0x00ede53f` * |
| `setFee(uint16)` | 522 | owner/POOLS_ADMINISTRATOR, only if DYNAMIC_FEE off | (currently inert: DYNAMIC_FEE is on → `dynamicFeeActive()` reverts; fee is plugin-driven) |
| `sync()` | 536 | **only `plugin`** | plugin `0xe33a2429` |
| `skim()` | 544 | **only `plugin`** → sends `balance-reserve` excess to the plugin | plugin `0xe33a2429` (excess only; currently 0) |

\* `0x00ede53f39415e64c78eebd02ad9d383b3a0c0f1` is a **contract** (codesize 3286) holding POOLS_ADMINISTRATOR + CUSTOM_POOL_DEPLOYER. READ of its bytecode: every setter path (`setPluginConfig`/`setCommunityFee`/`setTickSpacing`/`setPlugin`) is gated by an internal check that recomputes `factory.<customPoolByPair>(msg.sender, token0, token1) == pool` ("Only deployer"). Because `0x51f0` is a **default** pool (confirmed via `poolByPair`), this wrapper's deployer-gate does **not** grant anyone admin over the HYDX/USDC pool. INFERRED: not a practical authority path for this pool; listed for completeness.

**LIVE role holders on factory `0x36077d39`** (`getRoleMember*`):
- DEFAULT_ADMIN_ROLE (0x00): `[0x74266f2b206d1359b83fc74949ef07176fb3ae03]` — the owner (auto-granted, `AlgebraFactory.sol:234-240`). Can grant/revoke every other role.
- POOLS_ADMINISTRATOR (`keccak('POOLS_ADMINISTRATOR')`): `[0x00ede53f…, 0xdead1f5af792afc125812e875a891b038f888258]`.
- ALGEBRA_BASE_PLUGIN_MANAGER: `[0xdead1f5a…]`.
- ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR: `[0xdead1f5a…]`.
- CUSTOM_POOL_DEPLOYER: `[0x00ede53f…]`.
- GUARD (security): **count 0 (empty)**.

**Factory owner `0x74266f2b206d1359b83fc74949ef07176fb3ae03` is a plain EOA** (LIVE `eth_getCode` = `0x`, single key, no multisig, `pendingOwner`=0, `renounceOwnershipStartTimestamp`=0). It is the supreme authority: DEFAULT_ADMIN_ROLE + passes all `hasRoleOrOwner` gates + owns the plugin-factory ProxyAdmin (see §5).

**No principal-withdraw function exists on the pool.** READ of the full pool: the only token-out paths are `swap` (requires input), `collect`/`burn` (only to the position owner), `flash` (requires repayment), `skim` (excess-over-reserves only, currently 0), and the periodic fee transfers to `communityVault`+`plugin` (bounded by accrued fees, `ReservesManager.sol:150-164, 172-239`). There is **no admin/plugin function that transfers the pool's LP-owned reserves**.

---

## 2. Plugin hook behavior — can the hook move pool value?

Source: `AlgebraUpgradeablePlugin_0xaf114d4f/contracts/AlgebraUpgradeablePlugin.sol` and the connector/impl files (each module is `delegatecall`ed from the proxy). Every hook is `onlyPool` (only the pool may invoke it).

- **beforeInitialize / afterInitialize** (`AlgebraUpgradeablePlugin.sol:134-145`): set default pluginConfig, seed the volatility oracle, and (MEV) call `mevxRouter.initializePool` in a `try/catch`. No value movement.
- **beforeModifyPosition** (`:148-165`): security check only — `_checkStatusOnBurn` (on remove) / `_checkStatus` (on add). Returns pluginFee = 0. **READ: cannot move tokens; it can only revert** (block mint/burn) per the security registry status.
- **afterModifyPosition** (`:168-180`): re-asserts `defaultPluginConfig()` into the pool. No value movement.
- **beforeSwap** (`:183-205`): `_checkStatus` (may revert), writes an oracle timepoint, and returns the swap fee. If `sender == mevxExecutor || tx.origin == mevxExecutor` → `finalFee = 1` (0.0001%); else dynamic fee from volatility. Returns pluginFee = **0** (no per-swap plugin fee is charged — consistent with LIVE `pluginFeePending = 0`). **READ: sets fee / can revert; does not receive or move tokens.** The fee only raises/lowers what a swapper pays into the pool.
- **afterSwap** (`:208-232`): (a) update farming virtual-pool tick; (b) `_triggerAlmRebalance(tick)` → **only if `rebalanceManager()!=0`** calls `IRebalanceManager(manager).obtainTWAPAndRebalance(...)` (`AlmPluginImplementation.sol:76-83`); (c) if `mevxRouter!=0`, `_mevxAfterSwap` calls `mevxRouter.constructArbitrageRoute` then `mevxExecutor.executeRoute(...)` then `profitDistributor.distributeProfit(...)` (`MevxPluginImplementation.sol:68-120`). These are **external CALLs to separate contracts**; the pool's reserves are never handed to them by this code.
- **beforeFlash / afterFlash** (`:235-247`): security check / config re-assert.

**Fee-recipient wiring (READ, `ReservesManager.sol:172-239`):** community fee accrues to `communityFeePending{0,1}` and is periodically `safeTransfer`ed to `communityVault`; plugin fee accrues to `pluginFeePending{0,1}` and is transferred to the `plugin` address, then `plugin.handlePluginFee` is called. Because beforeSwap returns pluginFee=0, the plugin currently accrues nothing.

**Plugin-held-token withdrawal (READ, `UpgradeableAbstractPlugin.sol:90-93`):** `collectPluginFee(token, amount, recipient)` does `_authorize(); SafeTransfer.safeTransfer(token, recipient, amount)` — moves **tokens held by the plugin** (i.e. accrued plugin fees) to any recipient, gated by `ALGEBRA_BASE_PLUGIN_MANAGER`/owner. It cannot reach the pool's reserves (different contract). Currently the plugin holds ~0.

**Conclusion (READ + INFERRED):** the hook's powers over the pool are: set the swap fee (incl. a near-zero fee for the MEV executor), and **revert** (freeze) swaps/mints/burns via the security check. It has **no code path to transfer the pool's LP reserves to itself or a third party.** The strongest hook-level capability is *griefing/freezing*, plus fee/MEV-flow capture — not principal drain. (See §4 for the plugin-logic-swap consideration.)

---

## 3. Community-fee flow (LIVE, behavioral) — this is the "unusual wiring"

The pool's `communityFee` is **100%** and `communityVault = 0xac396cab…`. So **100% of all swap fees leave the pool** as HYDX+USDC transfers to `0xac396cab`, and LPs receive **no** swap fees. `0xac396cab` is not a vanilla AlgebraCommunityVault — it is a **GaugeIncentiveCampaign** (a ve(3,3)/Solidly-style gauge). LIVE getters: `owner()=0xbe50ae49…`, `campaignManager()=0x416d1a1b…`, `poolAddress()=0x51f0…`, `internal_bribe()=0xb69b1c48…`, `permissionsRegistry()=0x3ea45157…`, `DISTRIBUTION()=0xc69e3ef3…` (VoterV5). Current gauge balance: 114 HYDX + 3.07 USDC (fees awaiting sweep).

Where the fees go (READ, `GaugeIncentiveCampaign_0x22d2480d/contracts/GaugeIncentiveCampaign.sol`):
- **`_claimFees()` (line 482-513):** sweeps the gauge's token0/token1 balances by `approve`+`IBribe(internal_bribe).notifyRewardAmount(...)` to the **internal bribe `0xb69b1c48`** → distributed to ve-voters who vote for this gauge. This is the destination of the pool's swap fees.
- The staking surface is disabled: `deposit/withdraw/getReward/earned/emergencyWithdraw/...` are all `pure`/revert stubs (`:124-232`). No LP stakes here; the gauge is purely a fee/emission conduit.
- `notifyRewardAmount` (`:250-283`, `onlyDistribution` = VoterV5) forwards **emissions** (not pool fees) to a Merkl/MetroM/Hydrex distributor, with a **fallback `safeTransfer` to `teamMultisig`** on failure (`:334, 420, 472`). LIVE `permissionsRegistry.teamMultisig() = 0x1ae3753d9b60743a89159ccff8e251c60b560311`.
- Owner-only setters: `setPermissionsRegistry`, `setCampaignManager` (`:114, 239`). No generic owner "sweep/recoverERC20" exists in this contract.

Who can redirect this fee stream:
- **At the pool:** `setCommunityVault(newAddr)` (owner `0x74266f2b` or POOLS_ADMINISTRATOR `0xdead1f5a`) redirects the entire 100% fee stream (plus the small accrued-but-unsent pending) to an arbitrary address. (READ `AlgebraPool.sol:514-519`.)
- **At the gauge:** its logic is upgradeable via the vault beacon `0x799b61d7` whose owner is `0xdb5a8524` (a beacon-admin contract) whose `owner()` is **`0xdf52b5a03e3f5a4178e4f63e8bc51abe691b898f`** — a malicious gauge impl could transfer out gauge-held balances (the accrued fees, currently ~$5). INFERRED: not a principal path; affects only fees sitting in the gauge.
- **Team control:** `owner`(`0xbe50ae49`) and `campaignManager`(`0x416d1a1b`) are both owned by `0x1ae3753d…` (the team multisig), which is also the `teamMultisig` treasury fallback. So the Hydrex team governs the fee/emission destination configuration.

INFERRED: the "unusual wiring" is intentional ve(3,3) tokenomics — swap fees are taken 100% as community fee and routed to voters via the gauge/bribe, rather than paid to LPs.

---

## 4. Can it be DRAINED or have its RULES CHANGED — and by whom (factual)

**Rules can be changed** by the pool administrators — LIVE: factory owner EOA `0x74266f2b` and POOLS_ADMINISTRATOR key `0xdead1f5a`. They can, on this pool: change the swap fee regime, tick spacing, community-fee %, **redirect the 100% community-fee stream** (`setCommunityVault`), **swap the live hook** (`setPlugin`), and change plugin config. (READ §1.)

**Plugin logic can be replaced protocol-wide.** READ `AlgebraUpgradeablePluginFactory.sol:242-244`: `upgradePlugins(newImpl)` → `UpgradeableBeacon(beacon).upgradeTo(newImpl)`, gated `onlyAdministrator` = `hasRoleOrOwner(ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR, …)`. LIVE the beacon `0x106937fc` is owned by the plugin factory `0xa8dd4c05`, and that role is held by `0xdead1f5a` (+ owner `0x74266f2b`). So **`0xdead1f5a` or `0x74266f2b` can swap the hook code for every Hydrex Algebra pool at once.** Additionally the plugin factory itself sits behind a TransparentUpgradeableProxy whose ProxyAdmin `0x2689ef6a` is owned by `0x74266f2b` (LIVE) — a second upgrade path for the same EOA.

**Direct drain of the $559K principal: no on-chain path found (READ).** Neither the pool admin roles, the plugin, nor a replaced/malicious plugin implementation has a function that transfers the pool's LP-owned reserves. The reserves are only removable by the position owners via `burn`+`collect`. Even a fully malicious plugin is bounded to: setting swap fees (a swapper must still choose to swap), capturing bounded per-swap plugin fees / MEV flow, and reverting hooks. INFERRED.

**But two strong control-over-principal levers exist, held by the factory owner:**
1. **Freeze (funds locked, not stolen).** READ `SecurityRegistry.sol:23-69` + `SecurityPluginImplementation.sol:33-59`: setting the pool/global status to `DISABLED` makes `checkStatusOnBurn` revert → **burns blocked → LPs cannot withdraw**; `BURN_ONLY` blocks swaps/adds but still lets LPs exit. Access: `DISABLED` requires GUARD-role or factory owner; re-`ENABLED`/`BURN_ONLY` requires the factory **owner** only. LIVE: registry `0x4cb52ea0`, `algebraFactory=0x36077d39`, `globalStatus=ENABLED(0)`, pool status = `ENABLED(0)` (not frozen), **GUARD holders = 0** → today only owner `0x74266f2b` can freeze, and only owner can un-freeze. Also `setSecurityRegistry` on the plugin is owner/`0xdead1f5a`-gated, so the registry itself can be swapped.
2. **Redirect the entire fee stream** via `setCommunityVault` (already 100% community fee). Ongoing revenue, not the sitting principal.

**Net:** rules and the entire fee stream are controllable by a **single EOA (`0x74266f2b`) and a single 7702 operator key (`0xdead1f5a`)**; the same two can replace the hook logic and freeze/lock withdrawals; but **no role can directly transfer out the LP principal** — the residual risk to principal is *freeze/lock* and *fee/MEV siphoning of flow*, not theft of the reserves.

---

## 5. Off-chain components (keepers/operators) in the trust path

| Component | On-chain address it authenticates as | What it decides / does | If the key misbehaves / is compromised |
|---|---|---|---|
| **Protocol operator key** | `0xdead1f5af792afc125812e875a891b038f888258` — **EIP-7702 EOA** (LIVE code `0xef0100…63c0c19a`, delegate `0x63c0c19a…`). Holds POOLS_ADMINISTRATOR + ALGEBRA_BASE_PLUGIN_MANAGER + ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR. | Off-chain-driven pool/plugin administration: setPlugin/config/fee/tickspacing/communityVault, setRebalanceManager, setMevx{Router,Executor,ProfitDistributor}, setSecurityRegistry, `collectPluginFee`, and **`upgradePlugins` (swap plugin logic for all pools)**. | An off-chain key that can rewrite every pool's hook code, redirect all fees, and reconfigure MEV/ALM. Not a direct principal-transfer, but full control of the pool's *rules* and hook code (see §4). Highest-leverage off-chain key in scope. |
| **MEV operator (MevX)** | Router `0xb32f9894…` + ProfitDistributor `0x53c67db9…` `owner()` = `0x000000077ac13a2fc7c7a154d28e6251a5e4648b` — **EIP-7702 EOA, same delegate `0x63c0c19a`**. Executor `0x3a980817…` (proxy, ProxyAdmin `0x0a70fa8e…`). Executor also gets `finalFee=1` in beforeSwap. | Off-chain keeper submits/relays the back-run: `afterSwap` calls `mevxRouter.constructArbitrageRoute` then `mevxExecutor.executeRoute` then `profitDistributor.distributeProfit`. Router computes routes; executor runs arbitrage with **its own** capital; distributor splits profit. | Captures/miscaptures the MEV that a swap creates (value that might otherwise accrue to LPs/other arbers), and enjoys near-zero swap fees. It uses its own funds and price is enforced by pool math, so it **cannot pull pool reserves**. Worst case: MEV profit is siphoned to the operator instead of the intended `recipient`/protocol, and the executor swaps fee-free. |
| **ALM rebalance keeper** | `rebalanceManager()` — LIVE **`0x0` (INACTIVE)**; `slow/fastTwapPeriod=0`. Settable by `0xdead1f5a`/owner. | Would drive `afterSwap → IRebalanceManager.obtainTWAPAndRebalance` to rebalance an ALM vault's positions. | Not in the current trust path (unset). If activated, a malicious rebalance manager is *called* during swaps but operates on the ALM vault's own positions, not the pool's other LPs. The $559K today is regular concentrated-liquidity positions, not ALM-managed. |
| **Security guardian** | GUARD role on factory `0x36077d39` — LIVE **empty**; plus factory owner `0x74266f2b`. | Off-chain emergency responder can set pool/global status to `DISABLED`/`BURN_ONLY`. | Can **freeze** the pool (block swaps and, with `DISABLED`, block LP withdrawals). Only the owner can un-freeze. Currently only the owner EOA holds this power. |
| **Gauge / campaign manager** | Gauge `owner 0xbe50ae49…` + `campaignManager 0x416d1a1b…`, both owned by team multisig `0x1ae3753d…`. VoterV5 `0xc69e3ef3…` drives `notifyRewardAmount`. | Off-chain configuration of how the 100%-community-fee stream + emissions are distributed (internal bribe / Merkl / MetroM / Hydrex), with `teamMultisig` fallback. | Controls the *destination* of the fee/emission stream (voters vs. team treasury), and (via vault beacon `0x799b61d7`→`0xdf52b5a0`) can upgrade the gauge logic. Affects fee flow, not pool principal. |

INFERRED across all rows: the actual *decision-maker* is off-chain in every case — a keeper/relayer/team key submits the transaction; the contracts only check that `msg.sender` (or `tx.origin`, for the MEV executor fee discount) matches the stored on-chain address. Compromise of `0xdead1f5a` is the systemic worst case (rule + hook-code control across all pools + can appoint the ALM/MEV/security config).

---

## 6. Authorities (power → LIVE holder)

```json
{
  "pool": "0x51f0b932855986b0e621c9d4db6eee1f4644d3d2",
  "pool_token0_HYDX": "0x00000e7efa313f4e11bfff432471ed9423ac6b30",
  "pool_token1_USDC": "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
  "pool_reserves": {"HYDX": 21548011.53, "USDC": 229900.91},
  "pool_communityFee_pct": 100,
  "pool_dynamic_fee_now_pct": 1.0,

  "factory": "0x36077d39cdc65e1e3fb65810430e5b2c4d5fa29e",
  "factory_owner_EOA": "0x74266f2b206d1359b83fc74949ef07176fb3ae03",
  "factory_owner_is_EOA": true,
  "role_DEFAULT_ADMIN": ["0x74266f2b206d1359b83fc74949ef07176fb3ae03"],
  "role_POOLS_ADMINISTRATOR": ["0x00ede53f39415e64c78eebd02ad9d383b3a0c0f1", "0xdead1f5af792afc125812e875a891b038f888258"],
  "role_ALGEBRA_BASE_PLUGIN_MANAGER": ["0xdead1f5af792afc125812e875a891b038f888258"],
  "role_ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR": ["0xdead1f5af792afc125812e875a891b038f888258"],
  "role_CUSTOM_POOL_DEPLOYER": ["0x00ede53f39415e64c78eebd02ad9d383b3a0c0f1"],
  "role_GUARD_security": [],

  "can_setPlugin_setFee_setCommunityFee_setTickSpacing_setCommunityVault": ["0x74266f2b206d1359b83fc74949ef07176fb3ae03", "0xdead1f5af792afc125812e875a891b038f888258"],
  "can_call_sync_skim": ["0xe33a242990780ab872ae986ad68206478fc85ae1 (the plugin)"],

  "plugin_proxy_hook": "0xe33a242990780ab872ae986ad68206478fc85ae1",
  "plugin_beacon": "0x106937fc03212a762be17d529893a32e47ba13a1",
  "plugin_beacon_owner": "0xa8dd4c05796801c734e99d5582e90e3a8bd88194 (AlgebraUpgradeablePluginFactory proxy)",
  "can_upgrade_plugin_logic (upgradePlugins)": ["0x74266f2b206d1359b83fc74949ef07176fb3ae03", "0xdead1f5af792afc125812e875a891b038f888258"],
  "plugin_factory_proxyAdmin": "0x2689ef6a746f1b253cd772fb045a7563505bed00",
  "plugin_factory_proxyAdmin_owner": "0x74266f2b206d1359b83fc74949ef07176fb3ae03",

  "communityVault_gauge": "0xac396cabf5832a49483b78225d902c0999829993",
  "communityVault_impl": "0x22d23d13aa0065ff3233cc7628f59b49dc80480d (GaugeIncentiveCampaign)",
  "communityVault_beacon": "0x799b61d720afc817c58d944c59c973f01dfa44c8",
  "communityVault_beacon_admin_owner": "0xdf52b5a03e3f5a4178e4f63e8bc51abe691b898f",
  "gauge_owner": "0xbe50ae4934305c7cdc449862e387ca0515f3402f (GaugeFactoryIncentiveCampaign)",
  "gauge_campaignManager": "0x416d1a1b4555f715a6d804fcc10805b44409096d",
  "team_multisig_treasury": "0x1ae3753d9b60743a89159ccff8e251c60b560311",
  "fee_destination_internal_bribe": "0xb69b1c48917cc055c76a93a748b5daa6efa39dee",
  "can_redirect_fee_stream (setCommunityVault)": ["0x74266f2b206d1359b83fc74949ef07176fb3ae03", "0xdead1f5af792afc125812e875a891b038f888258"],

  "security_registry": "0x4cb52ea0096606e7843754936944a860e6f12cb6",
  "security_status_now": "ENABLED",
  "can_freeze_DISABLED (block burns/withdrawals)": ["0x74266f2b206d1359b83fc74949ef07176fb3ae03", "<any GUARD holder — currently none>"],
  "can_unfreeze_or_BURN_ONLY": ["0x74266f2b206d1359b83fc74949ef07176fb3ae03"],

  "alm_rebalanceManager": "0x0000000000000000000000000000000000000000 (INACTIVE)",
  "mevx_router": "0xb32f9894753ee9356ac6734ecf544779c70b1829",
  "mevx_executor": "0x3a980817e1522c532cc504dba5f5fee9e9096ac5",
  "mevx_profitDistributor": "0x53c67db91f47923d26b0b85a345e484e32a6232f",
  "mevx_operator_owner": "0x000000077ac13a2fc7c7a154d28e6251a5e4648b (EIP-7702, delegate 0x63c0c19a)",

  "off_chain_keys": {
    "0xdead1f5af792afc125812e875a891b038f888258": "EIP-7702 protocol operator (pool+plugin admin, plugin-logic upgrade)",
    "0x000000077ac13a2fc7c7a154d28e6251a5e4648b": "EIP-7702 MEV operator (MevX router/executor/distributor)",
    "0x74266f2b206d1359b83fc74949ef07176fb3ae03": "factory owner EOA (supreme; also freeze authority)"
  }
}
```

## Reproduce (LIVE reads)
Helper: `scratchpad/eth.py` (`eth_call`, `get_storage`, `selector`, `keccak256`). Examples used:
`AlgebraPool.plugin()/communityVault()/globalState()/getReserves()`; `AlgebraFactory.owner()/getRoleMember(bytes32,uint256)/poolByPair`; plugin `rebalanceManager()/getMevx*()/getSecurityRegistry()`; beacon `0x106937fc.owner()/implementation()`; ERC-1967 beacon slot on `0xe33a2429`; `SecurityRegistry.getPoolStatus(pool)/globalStatus()`; `eth_getCode` on `0x74266f2b` (=0x, EOA) and `0xdead1f5a`/`0x00000007ac13` (=`0xef0100…`, EIP-7702).
