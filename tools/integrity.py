#!/usr/bin/env python3
"""Integrity check: diff bundled shared-library files (OpenZeppelin, Solady)
against genuine upstream at the version stated in each file header. Surfaces any
'doctored baseline' where a project ships a subtly-altered dependency copy."""
import os, re, json, urllib.request, difflib, hashlib

REPO="/home/user/cetong"

# Upstream raw bases by dependency root prefix
def upstream_url(relpath, version):
    # openzeppelin upgradeable
    if "openzeppelin-contracts-upgradeable" in relpath:
        sub = relpath.split("openzeppelin-contracts-upgradeable/",1)[1]  # contracts/...
        return f"https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts-upgradeable/v{version}/{sub}"
    if "openzeppelin-contracts" in relpath:
        sub = relpath.split("openzeppelin-contracts/",1)[1]
        return f"https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v{version}/{sub}"
    if relpath.startswith("@openzeppelin/contracts-upgradeable/"):
        sub = "contracts/" + relpath.split("@openzeppelin/contracts-upgradeable/",1)[1]
        return f"https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts-upgradeable/v{version}/{sub}"
    if relpath.startswith("@openzeppelin/contracts/"):
        sub = "contracts/" + relpath.split("@openzeppelin/contracts/",1)[1]
        return f"https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v{version}/{sub}"
    return None

def stated_version(text, default="4.9.4"):
    m = re.search(r"last updated v(\d+\.\d+\.\d+)", text)
    if m: return m.group(1)
    m = re.search(r"last updated v(\d+\.\d+)\)", text)
    if m: return m.group(1) + ".0"
    return default

def fetch(url):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=25) as r:
                return r.read().decode()
        except Exception as e:
            if attempt==2: return None
    return None

def norm(s):
    return s.replace("\r\n","\n").rstrip("\n")+"\n"

def check_contract_ozlib(contract_dir):
    results=[]
    for root,_,files in os.walk(contract_dir):
        for fn in files:
            if not fn.endswith(".sol"): continue
            full=os.path.join(root,fn)
            rel=os.path.relpath(full, contract_dir)
            if not re.search(r"openzeppelin", rel, re.I): continue
            txt=open(full).read()
            ver=stated_version(txt)
            url=upstream_url(rel, ver)
            if not url:
                results.append({"file":rel,"status":"NO_UPSTREAM_MAP","version":ver}); continue
            # Try the whole 4.9.x patch range (plus the stated version) and mark MATCH
            # against the first byte-identical upstream; only DIFF if none match.
            candidates=[]
            for v in ["4.9.4","4.9.3","4.9.5","4.9.6","4.9.2","4.9.1","4.9.0", ver]:
                if v not in candidates: candidates.append(v)
            matched_ver=None; up_ref=None
            for v in candidates:
                up=fetch(upstream_url(rel,v))
                if up is None: continue
                if up_ref is None: up_ref=(v,up)
                if norm(txt)==norm(up):
                    matched_ver=v; break
            if up_ref is None:
                results.append({"file":rel,"status":"UPSTREAM_UNREACHABLE","version":ver,"url":url}); continue
            if matched_ver:
                results.append({"file":rel,"status":"MATCH","version":matched_ver,
                    "sha":hashlib.sha256(norm(txt).encode()).hexdigest()[:16]})
            else:
                refv,up=up_ref
                diff=list(difflib.unified_diff(norm(up).splitlines(), norm(txt).splitlines(),
                          fromfile=f"upstream v{refv}", tofile="bundled", lineterm=""))
                results.append({"file":rel,"status":"DIFF","version":refv,
                    "sha_local":hashlib.sha256(norm(txt).encode()).hexdigest()[:16],
                    "diff":"\n".join(diff[:200])})
    return results

if __name__=="__main__":
    targets={
        "FlapTaxTokenV3_impl (the token logic)":"contracts/00-target/FlapTaxTokenV3_impl",
        "TaxProcessorUniV2_impl (holds funds)":"contracts/10-downstream/TaxProcessorUniV2_impl",
        "Dividend_impl (holds funds)":"contracts/10-downstream/Dividend_impl",
        "Portal_impl (launchpad authority)":"contracts/20-upstream/Portal_impl",
    }
    allres={}
    for label,d in targets.items():
        full=os.path.join(REPO,d)
        res=check_contract_ozlib(full)
        allres[label]=res
        n=len(res); m=sum(1 for r in res if r["status"]=="MATCH"); diff=sum(1 for r in res if r["status"]=="DIFF")
        other=n-m-diff
        print(f"{label}: {n} OZ files -> {m} MATCH, {diff} DIFF, {other} other")
        for r in res:
            if r["status"]!="MATCH":
                print(f"   [{r['status']}] {r['file']} (v{r.get('version')})")
    json.dump(allres, open(os.path.join(REPO,"integrity","_oz_diff_raw.json"),"w"), indent=2)
    print("\nwrote integrity/_oz_diff_raw.json")
