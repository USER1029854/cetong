#!/usr/bin/env python3
"""Mechanically enumerate every externally-reachable entry point (external/public
functions, fallback, receive, payable) for the bespoke in-scope Hydrex contracts.
Reads each contract's abi.json (impl ABI for proxied logic). Also greps source for
fallback()/receive(). Emits a structured inventory."""
import json, os, glob, re

REPO="/home/user/cetong/contracts"

# (label, callable_address, dir_glob_of_logic_source)
INSCOPE=[
 ("HydrexToken (target)","0x00000e7efa313f4e11bfff432471ed9423ac6b30","target/HydrexToken_*"),
 ("MinterUpgradeableV4 [proxy 0xa7d6]","0xa7d64625f45548a19b2a19e28e7546bb2839003e","mint-authority/MinterUpgradeableV4_*"),
 ("RevisedPhasedEmissionSchedule","0x5aaa65af617fa50041325f46ecee5613aaff2727","mint-authority/RevisedPhasedEmissionSchedule_*"),
 ("OptionTokenV4 (oHYDX)","0xa1136031150e50b015b41f1ca6b2e99e49d8cb78","options/OptionTokenV4_*"),
 ("OptionFeeDistributor [proxy 0xdb2f]","0xdb2fc14d19a35d9802ea2c275e5f9f17bc9665cc","options/OptionFeeDistributor_*"),
 ("SimpleFloorGuardian [proxy 0xa007]","0xa007970f94311b8c5ab46fb2a871bccd95662873","options/SimpleFloorGuardian_*"),
 ("AlgebraIntegralTwap","0xf524522bbd8fc020033d94f83b83f5b50c9b6ea7","options/AlgebraIntegralTwap_*"),
 ("VotingEscrowV2Upgradeable [proxy 0x25b2]","0x25b2ed7149fb8a05f6ef9407d9c8f878f59cd1e1","ve-core/VotingEscrowV2Upgradeable_*"),
 ("VoterV5 [proxy 0xc69e]","0xc69e3ef39e3ffbce2a1c570f8d3adf76909ef17b","ve-core/VoterV5_0x*"),
 ("VoterV5_GaugeLogic (delegatecall)","0x8cf73eb543c75ba5f2e188d3ce5f8682f2e7f0a3","ve-core/VoterV5_GaugeLogic_*"),
 ("VoterV5_ClaimLogic (delegatecall)","0x68ed6a9fd3fe6db26def56641c3b251278d8c21d","ve-core/VoterV5_ClaimLogic_*"),
 ("RewardsDistributorV2","0x6fca200fe1f71be1b8714acfb5e9d3a147cced42","ve-core/RewardsDistributorV2_*"),
 ("BribeV2 [proxy internal/external]","0xb69b1c48917cc055c76a93a748b5daa6efa39dee","liquidity/BribeV2_*"),
 ("BribeFactoryV4 [proxy 0x58b4]","0x58b4f302753003ffc1d70791775b93d0edc87dc1","ve-core/BribeFactoryV4_*"),
 ("PermissionsRegistry (voter)","0x3ea45157819c46323cf3a4a3cb93bf58aa7eb81d","governance/PermissionsRegistry_0x3ea4*"),
 ("PermissionsRegistry (feeDist)","0x41806e1af8c8ba32a2dcb289e52da7bd0a5bf2f7","governance/PermissionsRegistry_0x4180*"),
 ("GaugeIncentiveCampaign [proxy 0xac39 communityVault]","0xac396cabf5832a49483b78225d902c0999829993","liquidity/GaugeIncentiveCampaign_*"),
 ("IncentiveCampaignManager [proxy 0x416d]","0x416d1a1b4555f715a6d804fcc10805b44409096d","liquidity/IncentiveCampaignManager_*"),
 ("GaugeFactoryIncentiveCampaign [proxy 0xbe50]","0xbe50ae4934305c7cdc449862e387ca0515f3402f","liquidity/GaugeFactoryIncentiveCampaign_*"),
 ("Pair (Solidly HYDX/USDC)","0x605abd1873737ca9a9ec1cfa52cdfc8ef62c2e1d","liquidity/Pair_*"),
 ("PairFees","0xada56cd47fa32d96b835c5c54e54124a3a2403e5","liquidity/PairFees_*"),
 ("PoolEligibilityOracle [proxy 0xc98f]","0xc98fb7b58d4da6c93c4a62bbeaa60932abc96c33","ve-core/PoolEligibilityOracle_*"),
 ("VeArtProxy [proxy 0x7cba]","0x7cba848649bf2557bdf4af9b0d14bc614d8497bf","ve-core/VeArtProxy_HYDX_*"),
 ("AlgebraCustomPoolEntryPoint (POOLS_ADMIN)","0x00ede53f39415e64c78eebd02ad9d383b3a0c0f1","governance/AlgebraCustomPoolEntryPoint_*"),
]

def abi_for(dir_glob):
    dirs=glob.glob(os.path.join(REPO,dir_glob))
    for d in dirs:
        p=os.path.join(d,"abi.json")
        if os.path.exists(p):
            try: return json.load(open(p)), d
            except: pass
    return None, dirs[0] if dirs else None

def source_specials(d):
    """grep the bespoke .sol files for fallback/receive."""
    hits=set()
    if not d: return hits
    for f in glob.glob(os.path.join(d,"**","*.sol"),recursive=True):
        if "node_modules" in f or "@openzeppelin" in f or "/lib/" in f: continue
        try: txt=open(f).read()
        except: continue
        if re.search(r'\bfallback\s*\(',txt): hits.add("fallback()")
        if re.search(r'\breceive\s*\(\s*\)\s*external\s+payable',txt): hits.add("receive()")
    return hits

total_fns=0
lines=[]
summary=[]
for label,addr,dg in INSCOPE:
    abi,d=abi_for(dg)
    if abi is None:
        lines.append(f"\n### {label}\n  (ABI not found at {dg})")
        continue
    fns=[f for f in abi if f.get("type")=="function"]
    ext=[f for f in fns if f.get("stateMutability")!="view" and f.get("stateMutability")!="pure"]
    views=[f for f in fns if f.get("stateMutability") in ("view","pure")]
    payable=[f for f in fns if f.get("stateMutability")=="payable"]
    specials=source_specials(d)
    total_fns+=len(ext)
    lines.append(f"\n### {label}")
    lines.append(f"- callable at `{addr}`  ·  state-changing external/public: **{len(ext)}**  ·  view/pure: {len(views)}  ·  payable: {len(payable)}  ·  specials: {sorted(specials) or 'none'}")
    lines.append(f"- state-changing entry points:")
    for f in sorted(ext,key=lambda x:x['name']):
        args=",".join(i['type'] for i in f.get('inputs',[]))
        mut=f.get('stateMutability')
        lines.append(f"    - `{f['name']}({args})`{' [payable]' if mut=='payable' else ''}")
    summary.append((label,len(ext),len(views)))

print(f"TOTAL state-changing external/public entry points (in-scope bespoke): {total_fns}")
print("\nPer-contract counts:")
for l,e,v in summary:
    print(f"  {e:3d} state-changing / {v:3d} view   {l}")
open("/tmp/claude-0/-home-user-cetong/520ae842-2c7a-518c-8e5e-badb3a9ef459/scratchpad/entrypoints_raw.md","w").write("\n".join(lines))
print("\nraw inventory -> scratchpad/entrypoints_raw.md")
