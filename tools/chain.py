#!/usr/bin/env python3
"""BSC on-chain toolkit for the CETS contract audit-repo assembly.
Provides RPC (with endpoint fallback), Etherscan V2 getsourcecode, eth_call
readers, storage reads, and unprivileged-caller simulation via eth_call.
"""
import json, os, sys, time, urllib.request, urllib.error

# Provide your own key via env: export ETHERSCAN_API_KEY=... (Etherscan V2, any chain).
ETHERSCAN_KEY = os.environ.get("ETHERSCAN_API_KEY", "YOUR_ETHERSCAN_V2_API_KEY")
CHAINID = 56  # BSC
RPCS = [
    "https://bsc-dataseed.binance.org",
    "https://bsc-rpc.publicnode.com",
    "https://bsc-dataseed1.defibit.io",
    "https://bsc-dataseed2.defibit.io",
    "https://bsc-dataseed1.ninicoin.io",
]

def _post(url, payload, timeout=25):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())

def rpc(method, params, _id=1):
    """JSON-RPC call with endpoint fallback."""
    last = None
    for url in RPCS:
        try:
            resp = _post(url, {"jsonrpc": "2.0", "method": method, "params": params, "id": _id})
            if "result" in resp:
                return resp["result"]
            last = resp.get("error", resp)
        except Exception as e:
            last = str(e)
            continue
    raise RuntimeError(f"RPC {method} failed on all endpoints: {last}")

def get_code(addr, block="latest"):
    return rpc("eth_getCode", [addr, block])

def get_balance(addr, block="latest"):
    return int(rpc("eth_getBalance", [addr, block]), 16)

def get_storage(addr, slot, block="latest"):
    if isinstance(slot, int):
        slot = hex(slot)
    return rpc("eth_getStorageAt", [addr, slot, block])

def eth_call(to, data, frm=None, block="latest", value=None):
    tx = {"to": to, "data": data}
    if frm: tx["from"] = frm
    if value is not None: tx["value"] = hex(value) if isinstance(value, int) else value
    return rpc("eth_call", [tx, block])

def call_or_revert(to, data, frm=None, block="latest", value=None):
    """Return (ok, result_or_error). Uses eth_call; captures revert."""
    tx = {"to": to, "data": data}
    if frm: tx["from"] = frm
    if value is not None: tx["value"] = hex(value) if isinstance(value, int) else value
    last = None
    for url in RPCS:
        try:
            resp = _post(url, {"jsonrpc": "2.0", "method": "eth_call", "params": [tx, block], "id": 1})
            if "result" in resp:
                return True, resp["result"]
            if "error" in resp:
                return False, resp["error"]
        except Exception as e:
            last = str(e); continue
    return False, {"transport": last}

# ---- ABI helpers (minimal, no deps) ----
from eth_utils_min import keccak, to_checksum

def selector(sig):
    return "0x" + keccak(sig.encode()).hex()[:8]

def enc_addr(a):
    a = a.lower().replace("0x", "")
    return a.rjust(64, "0")

def enc_uint(n):
    return hex(n)[2:].rjust(64, "0")

def dec_addr(word):
    word = word.replace("0x", "")
    return to_checksum("0x" + word[-40:])

def dec_uint(word):
    word = word.replace("0x", "")
    return int(word, 16) if word else 0

def call_read(to, sig, args=None, frm=None, block="latest"):
    """Encode a simple call (address/uint args only) and return raw hex result."""
    data = selector(sig)
    for a in (args or []):
        if isinstance(a, str) and a.startswith("0x") and len(a) >= 40:
            data += enc_addr(a)
        elif isinstance(a, int):
            data += enc_uint(a)
        else:
            raise ValueError(f"unsupported arg {a}")
    return eth_call(to, data, frm=frm, block=block)

def read_addr(to, sig, args=None, block="latest"):
    r = call_read(to, sig, args, block=block)
    if r in ("0x", "0x0", None): return None
    return dec_addr(r)

def read_uint(to, sig, args=None, block="latest"):
    r = call_read(to, sig, args, block=block)
    if r in ("0x", "0x0", None): return 0
    return dec_uint(r)

def read_string(to, sig, args=None, block="latest"):
    r = call_read(to, sig, args, block=block)
    if not r or r == "0x": return None
    b = bytes.fromhex(r[2:])
    if len(b) >= 64:
        off = int.from_bytes(b[:32], "big")
        ln = int.from_bytes(b[off:off+32], "big")
        return b[off+32:off+32+ln].decode(errors="replace")
    return b.rstrip(b"\x00").decode(errors="replace")

def read_bool(to, sig, args=None, block="latest"):
    r = call_read(to, sig, args, block=block)
    return dec_uint(r) != 0 if r and r != "0x" else False

if __name__ == "__main__":
    # quick self-test
    print("chainId:", rpc("eth_chainId", []))
    print("block:", rpc("eth_blockNumber", []))
