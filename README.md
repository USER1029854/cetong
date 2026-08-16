# CETS — audit-ready contract repository

Everything an auditor needs to reason about the security of **CETS ("Cets On Gold")**
without going back to a block explorer. The core is a **source tree** of the target
and every contract it reaches, upstream and downstream, each as real, readable code.
This repo does **not** assess exploitability — it makes sure nothing that matters is
unread, unrecovered, or unnamed.

- **Target:** `0xb0c2ab5af4028461ace3f6e1c33a4ee1404e7777`
- **Chain:** BNB Smart Chain (BSC, chainId 56)
- **What it is:** an EIP-1167 clone of **FlapTaxTokenV3** (Flap launchpad). A meme
  token with a 3% buy/sell tax liquidated to **Tether Gold (XAUt)** and paid to
  holders as dividends.

## Start here

1. **[`TRUST_GRAPH.md`](./TRUST_GRAPH.md)** — the map. The whole contract graph in
   both directions, with a diagram and a pointer to where every contract's code
   lives. **Read this first.**
2. **[`UNRESOLVED.md`](./UNRESOLVED.md)** — what could not be pinned down: off-chain
   components, the one unverified implementation, and stated graph boundaries. Read
   before concluding anything is safe.
3. **[`live-state/`](./live-state/)** — current chain reality (roles, approvals,
   reserves, proxy targets) and the empirical unprivileged-caller simulation.
4. **[`integrity/`](./integrity/)** — proof the shared dependencies (OpenZeppelin,
   Solady, PancakeSwap, Safe) are genuine and unmodified.

## Repository layout

```
contracts/                        Full source of every contract in the graph
  00-target/
    CETS_token/                   the EIP-1167 clone shell (state lives here)
    FlapTaxTokenV3_impl/          the logic the clone runs   ← the token's real code
  10-downstream/                  what the target leans on
    TaxProcessor / *_impl         swaps tax→XAUt; HOLDS XAUt for holders
    Dividend / *_impl             books & pays XAUt dividends; HOLDS XAUt for holders
    XAUt_proxy / XAUt_impl        Tether Gold (quote & dividend asset)
    PancakePair / Router / Factory / WBNB    canonical PancakeSwap V2 + WBNB
    SwapRegistry_proxy / _impl    shared registry (impl UNVERIFIED, inactive for CETS)
  20-upstream/                    what holds power over the target
    Portal_proxy / Portal_impl    owner() of TaxProcessor & Dividend (the launchpad)
    ProxyAdmin_Portal / _SwapRegistry
    Safe_LaunchpadAdmin / Safe_FeeReceiver / *_singletons
  30-peripheral/
    MultiDexRouter                referenced by SwapRegistry (inactive for CETS)
recovered-behavior/               SwapRegistry (the one unverified impl): recovered
live-state/                       live-state.json/.md + simulation-unprivileged.md
integrity/                        integrity-report.md + raw diff data
tools/                            the scripts used to build this repo (reproducible)
```

Each contract directory holds the **complete Etherscan source tree** (preserving
`lib/`, `src/`, `@openzeppelin/` layout so it can be read or recompiled) plus an
`_etherscan_meta.json` (compiler version, optimizer, EVM version). Proxy/clone shells
carry a `README.md` and the raw `runtime-bytecode.hex`, and point to the
implementation directory that holds the code they actually run.

## The one thing to understand about this system

The token's own ownership is **renounced** and its ERC-20 logic is honest — but that
is the least interesting part. The XAUt that belongs to holders lives in two
**separate** contracts (`Dividend`, `TaxProcessor`) whose sweep functions are
`onlyOwner`, and their owner is a **Portal** contract controlled by a single 3-of-4
**launchpad multisig** that can also upgrade the Portal to arbitrary logic. The real
power over holder funds sits upstream of the token, in code the token never names.
`TRUST_GRAPH.md` and `UNRESOLVED.md` trace exactly that.

Because CETS is a clone of a shared Flap template, the two notable implementation
traits — tax liquidation with `amountOutMin = 0`, and owner-gated fund sweeps whose
owner is the launchpad Safe — are **platform-wide, not unique to CETS**.

## Reproducibility

`tools/` contains a dependency-free Python toolkit (`chain.py`, `eth_utils_min.py`
with a self-tested keccak-256, `etherscan.py`, `triage.py`, `simulate.py`,
`capture_livestate.py`, `integrity.py`). `tools/inventory.json` is the address
manifest that drives the tree. All findings above can be regenerated against live BSC
state; the snapshot in `live-state/live-state.json` is pinned to block 116,212,059.
