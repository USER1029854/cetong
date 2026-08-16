#!/usr/bin/env python3
"""Fetch a verified contract from Etherscan V2 (BSC) and write its full source
tree to disk, handling single-file, multi-file JSON, and double-brace formats.
Also writes a metadata sidecar. Usage: save_source.py <addr> <dest_dir> [label]
"""
import json, os, sys, re
from etherscan import getsourcecode

def parse_sources(res):
    src = res.get("SourceCode", "")
    name = res.get("ContractName", "Contract")
    if not src:
        return None, {}
    files = {}
    settings = {}
    # Multi-file: often wrapped in double braces {{...}}
    stripped = src.strip()
    if stripped.startswith("{{") and stripped.endswith("}}"):
        stripped = stripped[1:-1]
    if stripped.startswith("{"):
        try:
            obj = json.loads(stripped)
            if isinstance(obj, dict) and "sources" in obj:
                for path, v in obj["sources"].items():
                    files[path] = v.get("content", "")
                settings = obj.get("settings", {})
                return files, settings
            elif isinstance(obj, dict):
                # {path: {content:...}} form
                looks_multi = all(isinstance(v, dict) and "content" in v for v in obj.values())
                if looks_multi:
                    for path, v in obj.items():
                        files[path] = v.get("content", "")
                    return files, settings
        except json.JSONDecodeError:
            pass
    # Single-file
    files[f"{name}.sol"] = src
    return files, settings

def sanitize(path):
    # keep directory structure but strip leading slashes / .. / drive-like prefixes
    path = path.replace("\\", "/")
    path = re.sub(r"^[A-Za-z]:", "", path)
    parts = [p for p in path.split("/") if p not in ("", ".", "..")]
    return "/".join(parts) or "Contract.sol"

def save(addr, dest_dir, label=None):
    r = getsourcecode(addr)
    if r.get("status") != "1":
        print(f"ERROR getsourcecode: {r.get('result')}")
        return None
    res = r["result"][0]
    files, settings = parse_sources(res)
    if not files:
        print(f"{addr}: NOT VERIFIED (no source)")
        return {"verified": False, "address": addr, "meta": res}
    os.makedirs(dest_dir, exist_ok=True)
    written = []
    for path, content in files.items():
        sp = sanitize(path)
        full = os.path.join(dest_dir, sp)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(content)
        written.append(sp)
    meta = {
        "verified": True,
        "address": addr,
        "label": label,
        "ContractName": res.get("ContractName"),
        "CompilerVersion": res.get("CompilerVersion"),
        "OptimizationUsed": res.get("OptimizationUsed"),
        "Runs": res.get("Runs"),
        "EVMVersion": res.get("EVMVersion"),
        "Proxy": res.get("Proxy"),
        "Implementation": res.get("Implementation"),
        "ConstructorArguments": res.get("ConstructorArguments"),
        "LicenseType": res.get("LicenseType"),
        "files": sorted(written),
    }
    with open(os.path.join(dest_dir, "_etherscan_meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print(f"{addr}: saved {len(written)} file(s) -> {dest_dir}")
    for w in sorted(written):
        print("   ", w)
    return meta

if __name__ == "__main__":
    addr = sys.argv[1]
    dest = sys.argv[2]
    label = sys.argv[3] if len(sys.argv) > 3 else None
    save(addr, dest, label)
