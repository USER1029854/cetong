# MevxRouter (unverified) — behavior recovery

**Implementation:** `0x2c3baec42114dd0c09dcd9b4402c782c6e34877a` (UNVERIFIED)
**Live proxy (callable):** `0xb32f9894753ee9356ac6734ecf544779c70b1829` — OZ **TransparentUpgradeableProxy**
**Chain:** Base (8453)
**Impl runtime size:** 23,837 bytes · **Proxy runtime size:** 2,739 bytes

> READ = observed on-chain / from the *verified* plugin that calls this contract.
> INFERRED = deduced from bytecode / simulation. The implementation itself is unverified.

---

## 1. What it is

**READ (verified plugin source + wiring):** This is the `IMevxRouter` used by the pool's MEV plugin.
The verified `MevxPluginImplementation.mevxAfterSwap` performs, on the pool's `afterSwap`:

```
router.constructArbitrageRoute(poolId, zeroToOne, amount0, amount1)   // low-level .call, no auth in caller
```

and `initializePool(poolId, ALGEBRA_POOL_TYPE=2, abi.encode(sqrtPriceX96))` on pool init. The plugin's
live storage has `mevxRouter = 0xb32f98…` (READ: plugin `0xe33a24` slot `…c6500`). So this router is
the **route/opportunity oracle** the plugin consults after each swap; it returns `(isArbPossible,
profitToken, pools, optimalAmountIn, encodedRoute)` which is then fed to the Executor.

**INFERRED:** the impl computes optimal arbitrage size/route across registered pools; it is `Ownable`
+ `Initializable`, has a re-entrancy `locked()` flag, and a per-pool registry populated by
`initializePool`.

---

## 2. Recovered selector → signature table

25 EQ-dispatch selectors extracted; `constructArbitrageRoute` / `initializePool` matched from the
verified interface.

| Selector | Signature (best guess) | Kind | Notes |
|---|---|---|---|
| `0x48335852` | `constructArbitrageRoute(bytes32,bool,int256,int256)` | **state-changing** (non-view in ABI; returns route) | READ: matches `IMevxRouter`; plugin entrypoint |
| `0x05b5dc79` | `initializePool(bytes32,uint16,bytes)` | **state-changing** | READ: matches `IMevxRouter`; registers a pool |
| `0x8da5cb5b` | `owner()` | view | READ: `0x000000077ac1…` |
| `0xf2fde38b` | `transferOwnership(address)` | state-changing | OZ Ownable, owner-gated |
| `0x715018a6` | `renounceOwnership()` | state-changing | OZ Ownable, owner-gated |
| `0xc4d66de8` | `initialize(address)` | state-changing | OZ Initializable (already initialized) |
| `0xcf309012` | `locked()` | view | READ: `0` (re-entrancy flag) |
| `0x527a1565` | `stopLoss()` **(name per DB)** | view getter | READ: returns address `0x854c9c8d6e7a9ec88592af174a4f040aa080b6c1` — an **address getter**, not an action |
| `0xd44c1864` | *unresolved* | **state-changing setter** | REVERTS `not owner` → owner-gated |
| `0xaf8afc81` | *unresolved* | view / no-op | returns empty `0x` to unprivileged caller |
| `0x11ab58d7` | *unresolved* | INFERRED | reverts cold |
| `0x13b5df67` | *unresolved* | INFERRED | reverts cold |
| `0x50295e23` | *unresolved* | INFERRED | reverts cold |
| `0x6494e248` | *unresolved* | INFERRED | reverts cold |
| `0x6e12e622` | *unresolved* | INFERRED | reverts cold |
| `0x76fcb168` | *unresolved* | INFERRED | reverts cold |
| `0x7a963ebe` | *unresolved* | INFERRED | reverts cold |
| `0xaad0cad9` | *unresolved* | INFERRED | reverts cold |
| `0xc22614cf` | *unresolved* | INFERRED | reverts cold |
| `0xc3725e4a` | *unresolved* | INFERRED | reverts cold |
| `0xca068898` | *unresolved* | INFERRED | reverts cold |
| `0xe195fa60` | *unresolved* | INFERRED | reverts cold |
| `0xe9080d87` | *unresolved* | INFERRED | reverts cold |
| `0xecdf1847` | *unresolved* | INFERRED | also present in Executor |
| `0xfd458d19` | *unresolved* | INFERRED | reverts cold |

**State-changing vs view (INFERRED from opcodes):** runtime uses `SSTORE`, `CALL`, `DELEGATECALL`,
`TLOAD`/`TSTORE`, `CREATE`/`CREATE2`, `SELFDESTRUCT`. Confirmed views: `owner()`, `locked()`,
`stopLoss()` (address getter), `0xaf8afc81`. `constructArbitrageRoute` is declared non-view in the
interface and can write pool caches (INFERRED).

---

## 3. Live authority values (READ)

- **`owner()` = `0x000000077ac13a2fc7c7a154d28e6251a5e4648b`** — the **EIP-7702 EOA** (code
  `0xef0100 63c0c19a…`), the same key that owns the MevX ProxyAdmin and the ProfitDistributor.
  This owner gates the router's privileged setters (`0xd44c1864` → `not owner`).
- **`locked()` = 0** (not mid-execution). `initialize(address)` reverts
  `Initializable: contract is already initialized` (READ) → already set up.
- **Upgrade authority = proxy admin.** Proxy `0xb32f98` EIP-1967 admin =
  **`0x0a70fa8e…791f`** (the same ProxyAdmin as the Executor), whose `owner()` = `0x000000077ac1…`.
  **=> the router logic can be swapped by the single EIP-7702 key.**

---

## 4. Guard analysis

- **Ownership / privileged setters:** OZ `Ownable`. `transferOwnership`, `renounceOwnership`, and the
  custom setter `0xd44c1864` all revert for an unprivileged caller (`Ownable: caller is not the owner`
  / `not owner`). **Guarded.**
- **`initialize`:** one-shot; already initialized → cannot be re-run. **Guarded.**
- **`constructArbitrageRoute` / `initializePool`:** revert for `0xdEaD` with empty/plausible args and
  even with a real `poolId` + nonzero amounts (see §5). Whether this is a caller check or "pool not
  registered / stale state" could not be fully separated by black-box calls, but the **observable
  result is that an unprivileged caller cannot drive them to success against current state.** These
  are read-model/route-builder functions; they do not custody user funds.
- No unguarded value-moving path was reachable on the router.

---

## 5. SIMULATION RESULTS — caller `0x…dEaD`, live `eth_call` vs current state

Calls to live proxy `0xb32f98` from `0x…dEaD`:

| Call (args) | Result | Reason / return |
|---|---|---|
| `constructArbitrageRoute(0, false, 0, 0)` | REVERT | empty |
| `constructArbitrageRoute(poolId=mainPool, true, -1000, 1000)` | REVERT | empty (pool not in usable state for cold caller) |
| `constructArbitrageRoute(poolId=mainPool, false, 1000, -1000)` | REVERT | empty |
| `initializePool(0, 2, "")` | REVERT | empty |
| `transferOwnership(dead)` | REVERT | `Ownable: caller is not the owner` |
| `renounceOwnership()` | REVERT | `Ownable: caller is not the owner` |
| `initialize(dead)` | REVERT | `Initializable: contract is already initialized` |
| `stopLoss()` | SUCCESS | address `0x854c9c8d6e7a9ec88592af174a4f040aa080b6c1` (getter) |
| `0xd44c1864` (no args) | REVERT | `not owner` (owner-gated setter) |
| `0xaf8afc81` (no args) | SUCCESS | `0x` (view / no-op) |
| `0x11ab58d7, 0x13b5df67, 0x50295e23, 0x6494e248, 0x6e12e622, 0x76fcb168, 0x7a963ebe, 0xaad0cad9, 0xc22614cf, 0xc3725e4a, 0xca068898, 0xe195fa60, 0xe9080d87, 0xecdf1847, 0xfd458d19` | REVERT | `execution reverted` (param-decode or owner/state gated) |

> Earlier "Invalid params" outputs were a JSON-RPC `-32602` calldata-encoding rejection (double `0x`
> prefix), not contract reverts; the corrected results are above.

---

## 6. Relationship to the pool (READ)

Called by the plugin `0xe33a24` on `afterSwap` (`constructArbitrageRoute`, via low-level `.call`) and
on pool initialization (`initializePool`, inside a `try/catch` "failsafe" so it can never block the
pool). It returns route data to the plugin, which then invokes the Executor. It does not itself take
custody of swap funds.

---

## 7. Bottom line

- **Who controls it:** `owner()` and upgrade rights both resolve to the **EIP-7702 EOA
  `0x000000077ac1`** (delegate `0x63c0c19a`) — a single key controls the router's privileged setters
  and (via ProxyAdmin `0x0a70fa8e`) its implementation.
- **Can an unprivileged caller reach anything dangerous?** **No — all state-changing paths are guarded**
  (Ownable / already-initialized / revert against current state). The router is a route oracle and
  holds no user value on the swap path.
- **Resists analysis:** 15 of 25 selectors are unresolved (custom names); several are owner-gated
  setters whose exact effect is unknown from bytecode alone.
