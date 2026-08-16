# SwapRegistry implementation — UNVERIFIED

- **Address:** `0x9a681bC1350636BBf81085207cde7485dAa67a65`
- **Status:** implementation source is **NOT verified** on the explorer.
- **Behind proxy:** `0x644A8f560138418bAD4EdEFC7c17878a3c2fBEB6` (see `../SwapRegistry_proxy/`)

There is no source to save here. The behavior was recovered by other means —
selector extraction, signature matching against the verified `ISwapRegistry`
interface, and live view calls through the proxy.

➡ See **`/recovered-behavior/SwapRegistry.md`** for the full recovered-behavior
artifact, and **`/recovered-behavior/SwapRegistry-impl-0x9a681bC1.runtime.hex`**
for the raw runtime bytecode.

**Note:** this registry path is **inactive for CETS** (dividendToken == quoteToken
== XAUt), so it moves no value for this token today.
