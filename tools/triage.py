#!/usr/bin/env python3
"""Triage a set of addresses: verified? name? EIP-1167 clone / EIP-1967 proxy?
code size? Resolve implementation addresses. Prints a table and emits JSON."""
import json, sys
from chain import get_code, get_storage, rpc
from eth_utils_min import to_checksum
from etherscan import getsourcecode

EIP1967_IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
EIP1967_ADMIN_SLOT = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
EIP1967_BEACON_SLOT = "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50"

def clone_impl(code):
    c = code[2:] if code.startswith("0x") else code
    # standard EIP-1167
    if c.startswith("363d3d373d3d3d363d73") and c.endswith("5af43d82803e903d91602b57fd5bf3"):
        return to_checksum("0x" + c[20:60])
    # vyper/optimized variants: look for 73<addr>5af43d
    import re
    m = re.search(r"73([0-9a-f]{40})5af43d", c)
    if m and len(c) < 200:
        return to_checksum("0x" + m.group(1))
    return None

def eip1967_impl(addr):
    slot = get_storage(addr, EIP1967_IMPL_SLOT)
    if slot and int(slot, 16) != 0:
        return to_checksum("0x" + slot[-40:])
    return None

def triage(addr):
    addr = to_checksum(addr)
    code = get_code(addr)
    info = {"address": addr, "codeSize": (len(code) - 2) // 2}
    if code == "0x" or code == "0x0":
        info["type"] = "EOA_or_empty"
        return info
    ci = clone_impl(code)
    if ci:
        info["type"] = "EIP1167_clone"
        info["implementation"] = ci
    else:
        e1967 = eip1967_impl(addr)
        if e1967:
            info["type"] = "EIP1967_proxy"
            info["implementation"] = e1967
        else:
            info["type"] = "contract"
    # verification
    try:
        r = getsourcecode(addr)
        if r.get("status") == "1":
            res = r["result"][0]
            info["verified"] = len(res.get("SourceCode", "")) > 0
            info["name"] = res.get("ContractName")
            info["etherscanProxy"] = res.get("Proxy")
            info["etherscanImpl"] = res.get("Implementation") or None
        else:
            info["verified"] = False
    except Exception as e:
        info["verified"] = None
        info["verifyError"] = str(e)
    # if it's a proxy/clone, also triage the implementation verification
    impl = info.get("implementation")
    if impl:
        try:
            r = getsourcecode(impl)
            if r.get("status") == "1":
                res = r["result"][0]
                info["implVerified"] = len(res.get("SourceCode", "")) > 0
                info["implName"] = res.get("ContractName")
            else:
                info["implVerified"] = False
        except Exception as e:
            info["implVerified"] = None
    return info

if __name__ == "__main__":
    addrs = sys.argv[1:]
    out = []
    for a in addrs:
        try:
            info = triage(a)
        except Exception as e:
            info = {"address": a, "error": str(e)}
        out.append(info)
        line = f"{info.get('address')}  {info.get('type','?'):16} verified={info.get('verified')}"
        if info.get("name"): line += f"  name={info['name']}"
        if info.get("implementation"): line += f"  impl={info['implementation']} implVerified={info.get('implVerified')} implName={info.get('implName')}"
        print(line)
    print("\nJSON:")
    print(json.dumps(out, indent=2))
