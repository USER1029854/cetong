# tools — reproducible on-chain toolkit

Dependency-free Python (stdlib only) used to build this repo against live BSC state.
No `web3`/`pycryptodome` needed — `eth_utils_min.py` ships a self-tested keccak-256.

| File | Purpose |
|---|---|
| `eth_utils_min.py` | keccak-256, EIP-55 checksum, mapping-slot math (run directly = self-test) |
| `chain.py` | JSON-RPC with public-BSC-endpoint fallback; `eth_call`/`getCode`/`getStorageAt`; ABI read helpers; revert-capturing `call_or_revert` |
| `etherscan.py` | Etherscan V2 (BSC) `getsourcecode`, throttled to the free-tier rate; bytecode selector extraction; openchain 4byte lookup |
| `save_source.py` | write a verified contract's full multi-file source tree to disk |
| `triage.py` | classify an address: EOA / contract / EIP-1167 clone / EIP-1967 proxy; resolve implementation; verification status |
| `simulate.py` | simulate value-moving functions from an unprivileged address (`eth_call`), decode reverts, dump live balances/config |
| `capture_livestate.py` | write the block-pinned `live-state/live-state.json` |
| `integrity.py` | diff bundled OpenZeppelin/Solady against genuine upstream tags |
| `inventory.json` | the address manifest that drives the whole tree |
| `sim_output.txt` | captured output of `simulate.py` at assembly time |

## Notes / environment constraints encountered

- The free Etherscan V2 tier serves `getsourcecode` for BSC but **blocks** the
  `proxy` (raw `eth_*`), `logs`, and `getcontractcreation` modules for this chain —
  hence bytecode, storage, and simulation go through public BSC RPCs directly, and
  role-holders were found via `hasRole` probes rather than event logs.
- RPC endpoints used: `bsc-dataseed.binance.org`, `bsc-rpc.publicnode.com`,
  `bsc-dataseed1/2.defibit.io`, `bsc-dataseed1.ninicoin.io` (with fallback).

Re-run examples:
```
python3 eth_utils_min.py                  # keccak self-test
python3 triage.py 0x<addr> [0x<addr> ...] # classify addresses
python3 simulate.py                       # unprivileged simulation + live balances
python3 capture_livestate.py              # refresh the live-state snapshot
python3 integrity.py                      # re-diff OZ against upstream
```
