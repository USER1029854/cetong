# TaxProcessor (clone)

- **Address:** `0xfe03d87c2539E1946C402E948312565db8b697D4`
- **Kind:** EIP1167 clone (state lives here, logic via delegatecall to impl)
- **Implementation:** `0x886301F6A7082C283086e7Fd63C3cAbB12a57d40`
- **Verified (shell):** True

## Role in the graph

Holds collected tax; swaps CETS->XAUt via PancakeSwap and routes to fee/market/dividend. HOLDS XAUt for holders. owner = Portal.

## Runtime bytecode

The on-chain runtime bytecode at this address is saved in `runtime-bytecode.hex` (45 bytes). 
The code that actually executes lives at the implementation `0x886301F6A7082C283086e7Fd63C3cAbB12a57d40` — see its own directory for full source.
