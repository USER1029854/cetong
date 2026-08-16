# CETS token (Cets On Gold)

- **Address:** `0xb0c2ab5af4028461ace3f6e1c33a4ee1404e7777`
- **Kind:** EIP1167 clone (state lives here, logic via delegatecall to impl)
- **Implementation:** `0x024f18294970b5c76c0691b87f138a0317156422`
- **Verified (shell):** True

## Role in the graph

The target. ERC20 with 3% buy/sell tax paid out as XAUt (Tether Gold) dividends. State (balances, config, owner) lives here; logic runs from the implementation via delegatecall.

## Runtime bytecode

The on-chain runtime bytecode at this address is saved in `runtime-bytecode.hex` (45 bytes). 
The code that actually executes lives at the implementation `0x024f18294970b5c76c0691b87f138a0317156422` — see its own directory for full source.
