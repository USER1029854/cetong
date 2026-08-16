# Dividend (clone)

- **Address:** `0x25765FAc1B94173bd60F0874a072dc4FA78FB3cF`
- **Kind:** EIP1167 clone (state lives here, logic via delegatecall to impl)
- **Implementation:** `0xcc11687b2389AE68b38c74495714781B11E40d71`
- **Verified (shell):** True

## Role in the graph

Tracks holder shares and distributes XAUt dividends. HOLDS XAUt for holders. emergencyWithdraw(token,amount,to) onlyOwner sweep. owner = Portal.

## Runtime bytecode

The on-chain runtime bytecode at this address is saved in `runtime-bytecode.hex` (45 bytes). 
The code that actually executes lives at the implementation `0xcc11687b2389AE68b38c74495714781B11E40d71` — see its own directory for full source.
