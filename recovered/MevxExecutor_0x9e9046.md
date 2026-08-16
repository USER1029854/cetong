# MevxExecutor (unverified) — behavior recovery

**Implementation:** `0x9e904666504580af8562b90d0a54786ae07ae9c7` (UNVERIFIED)
**Live proxy (callable):** `0x3a980817e1522c532cc504dba5f5fee9e9096ac5` — OZ **TransparentUpgradeableProxy**
**Chain:** Base (8453)
**Impl runtime size:** 23,806 bytes · **Proxy runtime size:** 2,739 bytes

> Method note: nothing here is from verified source of the implementation (it is unverified).
> Statements are split into **READ** (directly observed on-chain: bytecode, storage, `eth_call`
> results, or read from the *verified* plugin that calls this contract) and **INFERRED**
> (deduced from bytecode selectors / simulation behavior). The impl bytecode contains none of
> the revert strings seen at runtime except where noted, so revert reasons are quoted from live
> `eth_call` responses.

---

## 1. What it is

**READ (from verified plugin source + on-chain wiring):** This is the `IMevxExecutor` referenced by
the pool's MEV plugin. The verified `MevxPluginImplementation` (`0xaf11628e…`, source in
`contracts/liquidity/AlgebraUpgradeablePlugin_0xaf114d4f/@cryptoalgebra/mevx-plugin/`) calls, inside
`mevxAfterSwap` (the pool's `afterSwap` hook):

```
IMevxExecutor(mevxExecutor).executeRoute(encodedRoute, pools, amountIn, address(profitDistributor))
```

where `mevxExecutor` is read live from the plugin's ERC-7201 storage and equals the **executor proxy
`0x3a9808…`** (READ: plugin `0xe33a24…` storage slot `…c6501` = `0x3a9808…`).

**INFERRED (from selector set):** The implementation is a **multi-DEX flash-arbitrage executor**. Its
dispatcher exposes swap callbacks for Uniswap-V2/V3, PancakeV3, Algebra, Uniswap-V4
(`unlockCallback`/`lockAcquired`), and flash-loan receivers for Balancer-V2 (`receiveFlashLoan`) and
Morpho (`onMorphoFlashLoan`), plus internal swap helpers (`swapUniV2/V3`, `…ExactInWithBalanceOf`).
This is the standard shape of an atomic arbitrage router/executor.

---

## 2. Recovered selector → signature table

37 EQ-dispatch selectors were extracted from the runtime dispatcher (PUSH4/EQ pattern), resolved via
openchain/4byte. `executeRoute` was matched by computing the selector from the verified interface.

| Selector | Signature (best guess) | Kind | Notes |
|---|---|---|---|
| `0xb64bc2b3` | `executeRoute(bytes,address[],uint256,address)` | **state-changing** | READ: matches `IMevxExecutor`; the plugin's entrypoint |
| `0xfa461e33` | `uniswapV3SwapCallback(int256,int256,bytes)` | state-changing | DEX pay-callback |
| `0x2c8958f6` | `algebraSwapCallback(int256,int256,bytes)` | state-changing | DEX pay-callback |
| `0x23a69e75` | `pancakeV3SwapCallback(int256,int256,bytes)` | state-changing | DEX pay-callback |
| `0x10d1e85c` | `uniswapV2Call(address,uint256,uint256,bytes)` | state-changing | V2 flash/callback |
| `0xf04f2707` | `receiveFlashLoan(address[],uint256[],uint256[],bytes)` | **state-changing** | Balancer-V2 flash receiver — **see §4/§5** |
| `0x31f57072` | `onMorphoFlashLoan(uint256,bytes)` | state-changing | Morpho flash receiver (guarded) |
| `0x91dd7346` | `unlockCallback(bytes)` | state-changing | Uniswap-V4 unlock callback |
| `0xab6291fe` | `lockAcquired(bytes)` | state-changing | V4 / Balancer-V3 lock callback |
| `0x9a7bff79` | `hook(address,uint256,uint256,bytes)` | state-changing | generic V2-style callback |
| `0x69b4fad1` | `omniCall(address,uint256,uint256,bytes)` | state-changing | generic V2-style callback |
| `0xc8dc370b` | `swapUniV3(uint256,uint256,address,bytes)` | state-changing | internal swap helper (external) |
| `0x02aabb5e` | `swapUniV2(uint256,uint256,address,bytes)` | state-changing | internal swap helper (external) |
| `0x284719a4` | `swapUniV3ExactInWithBalanceOf(uint256,address,bytes)` | state-changing | swaps executor's own balance |
| `0xa4dcb9c5` | `swapUniV2ExactInWithBalanceOf(uint256,address,bytes)` | state-changing | swaps executor's own balance |
| `0xaaf5eb68` | `PRECISION()` | view | READ: returns `1e18` |
| `0x02b74f19` | *unresolved* | INFERRED swap/callback helper | not in signature DBs |
| `0x12e3b143` | *unresolved* | INFERRED | |
| `0x1ddfe427` | *unresolved* | INFERRED | |
| `0x304a0ef1` | *unresolved* | INFERRED | |
| `0x363d0423` | *unresolved* | INFERRED | |
| `0x388c1d39` | *unresolved* | INFERRED | |
| `0x44978557` | *unresolved* | INFERRED | |
| `0x47de9669` | *unresolved* | INFERRED | |
| `0x6aac9044` | *unresolved* | INFERRED | |
| `0x7073fedb` | *unresolved* | INFERRED | |
| `0x95cf1015` | *unresolved* | INFERRED | |
| `0x9f6273ab` | *unresolved* | INFERRED | |
| `0xa07eb17b` | *unresolved* | INFERRED | |
| `0xaf27ce8a` | *unresolved* | INFERRED | |
| `0xb1dbfffc` | *unresolved* | INFERRED | |
| `0xcd1f2edb` | *unresolved* | INFERRED | |
| `0xdb7631a0` | *unresolved* | INFERRED | |
| `0xe0a9def0` | *unresolved* | INFERRED | |
| `0xecdf1847` | *unresolved* | INFERRED | also present in Router |
| `0xf088a90a` | *unresolved* | INFERRED | |
| `0xf54e63e1` | *unresolved* | INFERRED | |

**State-changing vs view (INFERRED from opcode presence):** the runtime uses `SSTORE`, `CALL`,
`DELEGATECALL`, `CREATE`/`CREATE2`, `SELFDESTRUCT`, and transient `TLOAD`/`TSTORE`. `PRECISION()` is
the only confirmed pure view. All callbacks/route functions are state-changing (they move tokens via
`CALL`). The presence of `TLOAD`/`TSTORE` strongly suggests a **transient re-entrancy / expected-caller
lock** used to gate callbacks during an in-progress route (INFERRED).

---

## 3. Live authority values (READ)

- **Not `Ownable`.** `owner()` (`0x8da5cb5b`) is **not** in the dispatcher; calling it returns empty
  `0x` (falls through). There is no on-contract admin role on the implementation logic.
- **Executor storage (READ, proxy `0x3a9808`):** slot 0 = `0xb32f9894…` (the **Router** proxy),
  slot 2 = `0xb32f9894…` (Router again), slots 1,3–12 = 0. No owner/authorized-EOA slot.
- **Upgrade authority = the proxy admin.** Proxy `0x3a9808` EIP-1967 admin slot =
  **`0x0a70fa8e3f9dfe04348a2747fb2f5a2c6c5c791f`** (a ProxyAdmin, 2,632 bytes). That ProxyAdmin's
  `owner()` = **`0x000000077ac13a2fc7c7a154d28e6251a5e4648b`**.
- **`0x000000077ac1…` is an EOA under EIP-7702 (READ):** its code is exactly
  `0xef0100 63c0c19a282a1b52b07dd5a65b58948a07dae32b` — the EIP-7702 delegation designator, i.e. an
  externally-owned account delegating to smart-account impl `0x63c0c19a…` (11,185-byte contract).
  **=> The party that can replace the executor logic is a single EIP-7702-delegated key.**
- **Live token/ETH balances (READ):** executor `0x3a9808` holds **0 ETH, 0 HYDX (`0x00000e7e…`),
  0 USDC, 0 WETH**. It is fund-less in current state.

---

## 4. Guard analysis

| Function | Guard (observed) | Basis |
|---|---|---|
| `executeRoute` | **No caller restriction.** Only param validation (needs non-empty `pools`). | READ (sim §5) |
| `receiveFlashLoan` (Balancer) | **No `msg.sender` guard.** Proceeds into token-move logic on any caller. | READ (sim §5) |
| `onMorphoFlashLoan` | `msg.sender` must be Morpho — reverts `not-morpho-sender`. | READ (sim §5) |
| `uniswapV3/algebra/pancakeV3 SwapCallback`, `uniswapV2Call`, `hook`, `omniCall`, `unlockCallback`, `lockAcquired`, `swapUniV2/V3*` | Revert for an unprivileged caller with plausible zero/empty args (param-decode and/or transient-lock check). Caller-vs-param separation not fully isolated. | READ reverts (sim §5); INFERRED cause |

**INFERRED mechanism:** callbacks are meant to run only mid-route, gated by a transient lock set by
`executeRoute` (`TLOAD`/`TSTORE` present); when called cold they revert. `executeRoute` and
`receiveFlashLoan` are the two entrypoints reachable cold by anyone.

---

## 5. SIMULATION RESULTS — caller `0x…dEaD`, live `eth_call` vs current state

Calls made to the **live proxy `0x3a9808`** from `0x000000000000000000000000000000000000dEaD`.
(Note: an earlier run showed "Invalid params" for every arg-bearing call — that was a JSON-RPC
`-32602` malformed-calldata rejection from a double `0x` prefix, **not** a contract revert; results
below are the corrected run.)

| Call (args) | Result | Reason / return |
|---|---|---|
| `executeRoute("", [], 0, dead)` | REVERT | empty (empty `pools` → param revert) |
| `executeRoute("", [], 1e18, dead)` | REVERT | empty |
| `executeRoute(0x00·32, [USDC], 1, dead)` — **from dead** | **SUCCESS** (`0x`) | permissionless; no caller gate |
| `executeRoute(0x00·32, [USDC], 1, dead)` — from plugin `0xe33a24` | SUCCESS (`0x`) | same as from dead → not caller-gated |
| `receiveFlashLoan([], [], [], "")` | **SUCCESS** (`0x`) | no `msg.sender` guard; no-op on empty |
| `receiveFlashLoan([USDC], [1], [0], 0x00·32)` | REVERT | `ERC20: transfer to the zero address` — **proceeds into a token transfer** decoded from `userData` |
| `onMorphoFlashLoan(0, "")` | REVERT | `not-morpho-sender` (guarded) |
| `uniswapV3SwapCallback(1,-1,"")` | REVERT | empty |
| `algebraSwapCallback(1,-1,"")` | REVERT | empty |
| `pancakeV3SwapCallback(1,-1,"")` | REVERT | empty |
| `uniswapV2Call(dead,1,0,"")` | REVERT | empty |
| `unlockCallback("")` | REVERT | empty |
| `lockAcquired("")` | REVERT | empty |
| `hook(dead,1,0,"")` | REVERT | empty |
| `omniCall(dead,1,0,"")` | REVERT | empty |
| `swapUniV3(1,0,dead,"")` | REVERT | empty |
| `swapUniV2(1,0,dead,"")` | REVERT | empty |
| `swapUniV3ExactInWithBalanceOf(0,dead,"")` | REVERT | empty |
| `swapUniV2ExactInWithBalanceOf(0,dead,"")` | REVERT | empty |
| `PRECISION()` | SUCCESS | `1e18` |

---

## 6. Relationship to the pool (READ, from verified plugin)

On every swap, the pool → plugin `0xe33a24` (`afterSwap`) → delegatecalls verified
`MevxPluginImplementation.mevxAfterSwap` → **low-level `call` to Router `0xb32f98`.constructArbitrageRoute**;
if arb is possible, **`try` `Executor 0x3a9808.executeRoute(encodedRoute, pools, amountIn, profitDistributor)`**
inside a `try/catch` (so a reverting executor cannot block swaps), then
`profitDistributor.distributeProfit(configId, profitToken, recipient)`. `msg.sender` seen by the
executor in that path is the plugin proxy `0xe33a24`.

---

## 7. Bottom line

- **Who controls it:** no on-logic owner; the **proxy** is upgradeable by ProxyAdmin `0x0a70fa8e`,
  owned by the **EIP-7702 EOA `0x000000077ac1`** (delegate `0x63c0c19a`). A single key can swap the
  entire executor implementation.
- **Can an unprivileged caller reach anything dangerous?** **Yes, two entrypoints are permissionless**
  — `executeRoute(...)` and `receiveFlashLoan(...)` are reachable cold and operate on the executor's
  own balances / a caller-supplied route (`receiveFlashLoan` was observed proceeding into an ERC-20
  transfer decoded from attacker `userData`). **This is only safe because the executor is fund-less
  by design and currently holds 0 of all checked assets.** Any token or approval that ever rests on
  this contract between transactions is sweepable by an arbitrary caller (INFERRED impact). Morpho
  and the in-route callbacks are guarded.
- **Resists analysis:** 21 of 37 executor selectors do not resolve in signature databases (custom /
  proprietary swap-helper names). Their exact ABIs are unknown; classified as state-changing helpers
  from context only.
