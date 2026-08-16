# Portal — proxy (owner of TaxProcessor & Dividend)

- **Address:** `0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0`
- **Kind:** TransparentUpgradeableProxy (proxy; logic via delegatecall to impl)
- **Implementation:** `0x153378bbfa36411d34c20862725223E11665b74f`
- **Verified (shell):** True

## Role in the graph

THE OWNER of TaxProcessor and Dividend. Whoever controls this controls the onlyOwner sweeps (withdrawAll/emergencyWithdraw) and receiver config. Upgradeable by ProxyAdmin 0xB248...

## Runtime bytecode

The on-chain runtime bytecode at this address is saved in `runtime-bytecode.hex` (2882 bytes). 
The code that actually executes lives at the implementation `0x153378bbfa36411d34c20862725223E11665b74f` — see its own directory for full source.
