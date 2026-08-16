# Recovered behavior — SwapRegistry (unverified implementation)

This is the only contract in the CETS trust graph whose implementation source is
**not verified** on the explorer. Its behavior was recovered by other means:
proxy delegation of view calls, selector extraction from runtime bytecode, and
signature matching against the known `ISwapRegistry` interface (which *is* present
in the verified TaxProcessor source).

| | |
|---|---|
| Proxy (address stored by TaxProcessor as immutable `swapRegistry`) | `0x644A8f560138418bAD4EdEFC7c17878a3c2fBEB6` |
| Proxy kind | `TransparentUpgradeableProxy` (verified — see `contracts/10-downstream/SwapRegistry_proxy/`) |
| Implementation (live, from EIP-1967 slot) | `0x9a681bC1350636BBf81085207cde7485dAa67a65` — **UNVERIFIED** |
| Implementation runtime size | 11,045 bytes (saved: `SwapRegistry-impl-0x9a681bC1.runtime.hex`) |
| Proxy admin (can upgrade the impl) | `0x830C709805612ab460C3C1e249cfC058CB049d95` (OZ `ProxyAdmin`) |
| Proxy-admin owner | `0x8187F13ed6C7C9554AfE4Dd4C4D4960174846063` (**EOA** — single key) |

## Is it in CETS's value path? — No (currently inactive)

The TaxProcessor only calls the SwapRegistry in "Case 3": when the dividend token
differs from both the quote token and the tax token and therefore needs a DEX swap
during `dispatch()`. For CETS:

- `dividendToken` = `quoteToken` = XAUt (`0x21cAef8A…A3bf`)
- `converter` = `0x0`, `requiresMEVProtection()` = `false`

So the `_swapQuoteToDividendToken` path that reads the registry is **never reached**
for CETS. The registry is shared Flap-platform infrastructure that happens to be
wired into every TaxProcessor clone as an immutable. It is included here because it
is reachable from an address the target's TaxProcessor stores, and because its
implementation is unverified — but for CETS specifically it moves no value today.
If the launchpad admin ever called `setDividendToken` to a third token (an
`onlyOwner` function — owner = Portal), this path would activate.

## Recovered live configuration (read through the proxy)

| View | Value |
|---|---|
| `multiDexRouter()` | `0xDedF55b08a3f1c61576a4bd675825690e1eE99ec` (verified `MultiDexRouter`, see `contracts/30-peripheral/`) |
| `defaultThreshold()` | `2000000000000000000000` (2000e18) |
| `weth()` | `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c` (WBNB) |
| `isAllowedQuoteToken(XAUt)` | `false` |
| `isBlacklisted(XAUt)` | `false` |
| Access-control model | `AccessControl` (has `DEFAULT_ADMIN_ROLE()`, `REGISTRY_ADMIN_ROLE()`, `grantRole`, `hasRole`) — **not** `Ownable` (`owner()` reverts) |

## Selector recovery (31 selectors in bytecode)

24 of 31 selectors match the verified `ISwapRegistry` interface exactly; 4 more are
standard pool-inspection helpers; 3 remain unidentified.

Matched to `ISwapRegistry` / `AccessControl`:
`supportsInterface`, `quoteTokenThreshold`, `isAllowedQuoteToken`, `getRoleAdmin`,
`getTrustStatus`, `grantRole`, `setWhitelisted`, `weth`, `setQuoteTokenThreshold`,
`defaultThreshold`, `removeSwapPath`, `isSwapSupportedWithDetailedErrors`,
`setSwapPath`, `setBlacklisted`, `hasRole`, `multiDexRouter`, `DEFAULT_ADMIN_ROLE`,
`setAllowedQuoteToken`, `isSwapSupported`, `getSwapInfo`, `REGISTRY_ADMIN_ROLE`,
`initialize(address)`, `revokeRole`, `isBlacklisted`.

Extra pool-inspection helpers (identified via signature DB):
`getReserves()` (`0x0902f1ac`), `token0()` (`0x0dfe1681`), `v2Factory()`
(`0xb4b57c39`), `getPair(address,address)` (`0xe6a43905`) — consistent with a
registry that checks live pool liquidity when answering `isSwapSupported`.

Unidentified selectors (no signature-DB hit): `0x398102a4`, `0x7353f3af`,
`0xbc9589fd`. These are almost certainly additional view getters (e.g. a
`v3Factory`/config accessor) but could not be named. They are **read paths** in a
contract not on the CETS value path.

## Assessment

The unverified implementation is a faithful, slightly-richer implementation of the
known `ISwapRegistry` interface. Nothing in the selector set or live config is
anomalous, and the contract is not in CETS's active value path. The residual
unknowns are the 3 unnamed selectors and the fact that the source is not verified —
tracked in `UNRESOLVED.md`. The single-EOA upgrade key over this shared registry is
a platform-level trust concern (also in `UNRESOLVED.md`), not a CETS-specific one.
