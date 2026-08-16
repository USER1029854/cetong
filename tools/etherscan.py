#!/usr/bin/env python3
"""Etherscan V2 (BSC) source fetch + selector recovery helpers."""
import json, sys, time, urllib.request, urllib.parse
from chain import ETHERSCAN_KEY, CHAINID, get_code
from eth_utils_min import keccak

BASE = "https://api.etherscan.io/v2/api"

_LAST_CALL = [0.0]
_MIN_INTERVAL = 0.5  # <=2 calls/sec to stay under the 3/sec free-tier cap

def _throttle():
    dt = time.time() - _LAST_CALL[0]
    if dt < _MIN_INTERVAL:
        time.sleep(_MIN_INTERVAL - dt)
    _LAST_CALL[0] = time.time()

def _get(params, timeout=30):
    params = dict(params)
    params["chainid"] = CHAINID
    params["apikey"] = ETHERSCAN_KEY
    url = BASE + "?" + urllib.parse.urlencode(params)
    for attempt in range(5):
        try:
            _throttle()
            with urllib.request.urlopen(url, timeout=timeout) as r:
                resp = json.loads(r.read().decode())
            # Etherscan returns status 0 + rate-limit message; retry those
            msg = str(resp.get("result", "")) + str(resp.get("message", ""))
            if "rate limit" in msg.lower() and attempt < 4:
                time.sleep(1.2 * (attempt + 1))
                continue
            return resp
        except Exception as e:
            if attempt == 4:
                raise
            time.sleep(1.5 * (attempt + 1))

def getsourcecode(addr):
    return _get({"module": "contract", "action": "getsourcecode", "address": addr})

def getabi(addr):
    return _get({"module": "contract", "action": "getabi", "address": addr})

def is_verified(addr):
    r = getsourcecode(addr)
    if r.get("status") != "1":
        return False, r.get("result")
    res = r["result"][0]
    src = res.get("SourceCode", "")
    return (len(src) > 0), res

def contract_creation(addrs):
    """getcontractcreation supports up to 5 addresses comma-joined."""
    return _get({"module": "contract", "action": "getcontractcreation",
                 "address": ",".join(addrs)})

# ---- selector recovery from runtime bytecode ----
def extract_selectors(code_hex):
    """Heuristic: scan for PUSH4 (0x63) immediates used in the dispatcher.
    Returns sorted unique 4-byte selectors as hex strings."""
    if code_hex.startswith("0x"):
        code_hex = code_hex[2:]
    b = bytes.fromhex(code_hex)
    sels = set()
    i = 0
    n = len(b)
    while i < n:
        op = b[i]
        if op == 0x63 and i + 5 <= n:  # PUSH4
            sel = b[i+1:i+5].hex()
            sels.add("0x" + sel)
            i += 5
            continue
        # skip PUSH1..PUSH32 immediates
        if 0x60 <= op <= 0x7f:
            i += 1 + (op - 0x5f)
            continue
        i += 1
    # dispatcher selectors are those compared with EQ; keep plausible ones
    return sorted(sels)

def lookup_4byte(selector):
    """Query openchain.xyz signature DB for a selector."""
    url = f"https://api.openchain.xyz/signature-database/v1/lookup?function={selector}&filter=true"
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            data = json.loads(r.read().decode())
        entries = data.get("result", {}).get("function", {}).get(selector, [])
        return [e["name"] for e in entries]
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    addr = sys.argv[1]
    verified, res = is_verified(addr)
    print(f"{addr} verified={verified}")
    if verified:
        print("Name:", res.get("ContractName"), "Compiler:", res.get("CompilerVersion"))
