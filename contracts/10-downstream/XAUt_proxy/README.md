# XAUt (Tether Gold) — proxy

- **Address:** `0x21cAef8A43163Eea865baeE23b9C2E327696A3bf`
- **Kind:** TransparentUpgradeableProxy (proxy; logic via delegatecall to impl)
- **Implementation:** `0x9151434b16b9763660705744891fA906F660EcC5`
- **Verified (shell):** True

## Role in the graph

The quote/dividend asset. Real Tether Gold OFT on BSC, 6 decimals. UPGRADEABLE by its proxy admin (0xedaba0...). Every XAUt held by CETS's contracts and pool depends on this implementation.

## Runtime bytecode

The on-chain runtime bytecode at this address is saved in `runtime-bytecode.hex` (2227 bytes). 
The code that actually executes lives at the implementation `0x9151434b16b9763660705744891fA906F660EcC5` — see its own directory for full source.
