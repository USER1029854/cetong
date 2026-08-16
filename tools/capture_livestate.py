#!/usr/bin/env python3
"""Capture a block-stamped live-state snapshot to live-state/live-state.json
and a human-readable live-state.md."""
import json, os
from chain import rpc, read_addr, read_uint, read_bool, read_string, call_or_revert, selector, enc_addr, get_storage
from eth_utils_min import to_checksum

REPO="/home/user/cetong"
BLOCK = rpc("eth_blockNumber", [])
blk = rpc("eth_getBlockByNumber", [BLOCK, False])
BTS = int(blk["timestamp"], 16)
BN = int(BLOCK, 16)

T   = "0xb0c2ab5af4028461ace3f6e1c33a4ee1404e7777"
TP  = "0xfe03d87c2539E1946C402E948312565db8b697D4"
DIV = "0x25765FAc1B94173bd60F0874a072dc4FA78FB3cF"
PAIR= "0xdabbd019c0174BDAE6354f32b158D42e4A0E7489"
X   = "0x21cAef8A43163Eea865baeE23b9C2E327696A3bf"
ROUTER="0x10ED43C718714eb63d5aA57B78B54704E256024E"
PORTAL="0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0"
SR="0x644A8f560138418bAD4EdEFC7c17878a3c2fBEB6"
IMPL_SLOT='0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
ADMIN_SLOT='0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'

def bof(tok, who): return read_uint(tok, "balanceOf(address)", [who], block=BLOCK)
def eip1967_impl(a):
    s=get_storage(a,IMPL_SLOT,block=BLOCK); return to_checksum('0x'+s[-40:]) if int(s,16) else None
def eip1967_admin(a):
    s=get_storage(a,ADMIN_SLOT,block=BLOCK); return to_checksum('0x'+s[-40:]) if int(s,16) else None

snap = {"block": BN, "blockHex": BLOCK, "timestamp": BTS, "chain": "BSC (56)"}

# pool
ok,res = call_or_revert(PAIR, selector("getReserves()"), block=BLOCK)
h=res[2:]; r0=int(h[0:64],16); r1=int(h[64:128],16); rts=int(h[128:192],16)
snap["pool"] = {
    "address": PAIR, "token0": read_addr(PAIR,"token0()",block=BLOCK), "token1": read_addr(PAIR,"token1()",block=BLOCK),
    "reserve0_XAUt_raw": r0, "reserve0_XAUt": r0/1e6,
    "reserve1_CETS_raw": r1, "reserve1_CETS": r1/1e18,
    "blockTimestampLast": rts,
    "lpTotalSupply": read_uint(PAIR,"totalSupply()",block=BLOCK)/1e18,
    "kLast": read_uint(PAIR,"kLast()",block=BLOCK),
    "xaut_balanceOf_pair_raw": bof(X,PAIR), "cets_balanceOf_pair_raw": bof(T,PAIR),
    "reserves_match_balances": (bof(X,PAIR)==r0 and bof(T,PAIR)==r1),
}

# token config
ok,res=call_or_revert(T, selector("getPoolStateData()"), block=BLOCK)
h=res[2:]
st=int(h[0:64],16); buy=int(h[64:128],16); sell=int(h[128:192],16); lt=int(h[192:256],16); te=int(h[256:320],16); afe=int(h[320:384],16)
states=["BondingCurve","Migrating","TaxEnforcedAntiFarmer","TaxEnforced","TaxFree"]
snap["token"] = {
    "address": T, "name": read_string(T,"name()",block=BLOCK), "symbol": read_string(T,"symbol()",block=BLOCK),
    "decimals": read_uint(T,"decimals()",block=BLOCK), "totalSupply": read_uint(T,"totalSupply()",block=BLOCK)/1e18,
    "owner": read_addr(T,"owner()",block=BLOCK), "implementation_eip1167": "0x024f18294970b5c76c0691b87f138a0317156422",
    "state": st, "stateName": states[st] if st<len(states) else "?",
    "buyTaxBps": buy, "sellTaxBps": sell,
    "liquidationThreshold_CETS": lt/1e18,
    "taxExpirationTime": te, "antiFarmerExpirationTime": afe,
    "taxExpired_now": BTS>te, "antiFarmerExpired_now": BTS>afe,
    "cets_accrued_as_tax_on_token_raw": bof(T,T), "cets_accrued_as_tax_on_token": bof(T,T)/1e18,
    "cets_burned_dead": bof(T,"0x000000000000000000000000000000000000dEaD")/1e18,
    "self_approve_token_to_taxProcessor": read_uint(T,"allowance(address,address)",[T,TP],block=BLOCK),
    "pools_mainPool": read_bool(T,"pools(address)",[PAIR],block=BLOCK),
}

# fund-holding contracts
snap["funds_held_for_holders"] = {
    "TaxProcessor": {"address": TP, "owner": read_addr(TP,"owner()",block=BLOCK),
        "XAUt_raw": bof(X,TP), "XAUt": bof(X,TP)/1e6, "CETS": bof(T,TP)/1e18,
        "feeQuoteBalance": read_uint(TP,"feeQuoteBalance()",block=BLOCK),
        "lpQuoteBalance": read_uint(TP,"lpQuoteBalance()",block=BLOCK),
        "marketQuoteBalance": read_uint(TP,"marketQuoteBalance()",block=BLOCK),
        "pendingDividendQuoteTokenBalance": read_uint(TP,"pendingDividendQuoteTokenBalance()",block=BLOCK),
        "totalDividendTokenSent_raw": read_uint(TP,"totalDividendTokenSent()",block=BLOCK),
        "totalDividendTokenSent_XAUt": read_uint(TP,"totalDividendTokenSent()",block=BLOCK)/1e6,
        "converter": read_addr(TP,"converter()",block=BLOCK),
        "requiresMEVProtection": read_bool(TP,"requiresMEVProtection()",block=BLOCK),
    },
    "Dividend": {"address": DIV, "owner": read_addr(DIV,"owner()",block=BLOCK),
        "XAUt_raw": bof(X,DIV), "XAUt": bof(X,DIV)/1e6, "CETS": bof(T,DIV)/1e18,
        "totalShares_CETS": read_uint(DIV,"totalShares()",block=BLOCK)/1e18,
        "minimumShareBalance_CETS": read_uint(DIV,"minimumShareBalance()",block=BLOCK)/1e18,
    },
}

# authorities / roles
def hasrole(role_hex, who):
    data=selector("hasRole(bytes32,address)")+role_hex+enc_addr(who)
    ok,r=call_or_revert(PORTAL,data,block=BLOCK); return ok and int(r,16)==1
ZERO="0"*64
TOPSAFE="0x1f96BC88f0794060433Be5F3EC9159a9C4f08A3b"
snap["authorities"] = {
    "TaxProcessor.owner": read_addr(TP,"owner()",block=BLOCK),
    "Dividend.owner": read_addr(DIV,"owner()",block=BLOCK),
    "Portal_proxy": PORTAL,
    "Portal.implementation": eip1967_impl(PORTAL),
    "Portal.proxyAdmin": eip1967_admin(PORTAL),
    "Portal.DEFAULT_ADMIN_ROLE_held_by_launchpadSafe": hasrole(ZERO, TOPSAFE),
    "launchpadAdminSafe": TOPSAFE,
    "launchpadAdminSafe.threshold": read_uint(TOPSAFE,"getThreshold()",block=BLOCK),
    "feeReceiverSafe": "0x8a08D98CBB218fceB318Ecf3aBc1BA43D8A7aB0E",
    "XAUt.implementation": eip1967_impl(X),
    "XAUt.proxyAdmin": eip1967_admin(X),
    "SwapRegistry.implementation": eip1967_impl(SR),
    "SwapRegistry.proxyAdmin": eip1967_admin(SR),
    "marketAddress": read_addr(TP,"marketAddress()",block=BLOCK),
    "feeReceiver": read_addr(TP,"feeReceiver()",block=BLOCK),
    "dividendToken": read_addr(TP,"dividendToken()",block=BLOCK),
    "quoteToken": read_addr(TP,"getQuoteToken()",block=BLOCK),
}

os.makedirs(os.path.join(REPO,"live-state"), exist_ok=True)
with open(os.path.join(REPO,"live-state","live-state.json"),"w") as f:
    json.dump(snap, f, indent=2)
print("wrote live-state.json at block", BN, "ts", BTS)
print(json.dumps(snap["authorities"], indent=2))
print("reserves_match_balances:", snap["pool"]["reserves_match_balances"])
