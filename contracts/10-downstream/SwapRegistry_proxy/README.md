# SwapRegistry — proxy

- **Address:** `0x644A8f560138418bAD4EdEFC7c17878a3c2fBEB6`
- **Kind:** TransparentUpgradeableProxy (proxy; logic via delegatecall to impl)
- **Implementation:** `0x9a681bC1350636BBf81085207cde7485dAa67a65`
- **Verified (shell):** True

## Role in the graph

Immutable swapRegistry in TaxProcessor. Used ONLY when dividendToken != quoteToken (Case 3). INACTIVE for CETS (dividendToken == quoteToken == XAUt). Implementation is UNVERIFIED — behavior recovered.

## Runtime bytecode

The on-chain runtime bytecode at this address is saved in `runtime-bytecode.hex` (2837 bytes). 
The code that actually executes lives at the implementation `0x9a681bC1350636BBf81085207cde7485dAa67a65` — see its own directory for full source.
