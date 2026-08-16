#!/usr/bin/env python3
"""Empirical simulation of state-changing functions from an ARBITRARY UNPRIVILEGED
address against current BSC chain state, plus live-state capture. eth_call only —
no transactions sent. Decodes revert reasons."""
import json
from chain import call_or_revert, selector, enc_addr, enc_uint, eth_call, read_addr, read_uint, read_bool, read_string, get_storage
from eth_utils_min import to_checksum

ATTACKER = "0x1111111111111111111111111111111111111111"  # arbitrary unprivileged EOA

T   = "0xb0c2ab5af4028461ace3f6e1c33a4ee1404e7777"  # CETS token clone
TP  = "0xfe03d87c2539E1946C402E948312565db8b697D4"  # TaxProcessor clone
DIV = "0x25765FAc1B94173bd60F0874a072dc4FA78FB3cF"  # Dividend clone
PAIR= "0xdabbd019c0174BDAE6354f32b158D42e4A0E7489"  # PancakePair CETS/XAUt
X   = "0x21cAef8A43163Eea865baeE23b9C2E327696A3bf"  # XAUt
ROUTER="0x10ED43C718714eb63d5aA57B78B54704E256024E"

def decode_revert(err):
    """Decode {code, message, data} into a human revert reason."""
    if not isinstance(err, dict):
        return str(err)
    data = err.get("data")
    if isinstance(data, dict):  # some nodes nest
        data = data.get("data") or data.get("result")
    msg = err.get("message", "")
    if isinstance(data, str) and data.startswith("0x") and len(data) >= 10:
        sel = data[:10]
        if sel == "0x08c379a0":  # Error(string)
            try:
                b = bytes.fromhex(data[10:])
                off = int.from_bytes(b[:32], "big")
                ln = int.from_bytes(b[off:off+32], "big")
                return "Error: " + b[off+32:off+32+ln].decode(errors="replace")
            except Exception:
                return f"{msg} (raw {data[:20]})"
        if sel == "0x4e487b71":  # Panic(uint256)
            code = int(data[10:], 16)
            return f"Panic(0x{code:02x})"
        return f"{msg} (custom error {sel})"
    return msg or "reverted (no data)"

def sim(to, sig, args_enc="", label=None, frm=ATTACKER, value=None):
    data = selector(sig) + args_enc
    ok, res = call_or_revert(to, data, frm=frm, value=value)
    label = label or sig
    if ok:
        print(f"  [REACHABLE ] {label:48} -> ok (ret {res[:20]}{'...' if len(res)>20 else ''})")
    else:
        print(f"  [REVERT    ] {label:48} -> {decode_revert(res)}")
    return ok, res

print("="*90)
print("UNPRIVILEGED-CALLER SIMULATION  (from =", ATTACKER, ") — eth_call, no tx sent")
print("="*90)
print("\n--- TaxProcessor", TP, "(holds XAUt for holders) ---")
sim(TP, "withdrawAll(address,address)", enc_addr(X)+enc_addr(ATTACKER), "withdrawAll(XAUt -> attacker)")
sim(TP, "withdrawAll(address,address)", enc_addr("0x0000000000000000000000000000000000000000")+enc_addr(ATTACKER), "withdrawAll(quote/native -> attacker)")
sim(TP, "processTaxTokens(uint256)", enc_uint(1), "processTaxTokens(1)")
sim(TP, "setConverter(address)", enc_addr(ATTACKER), "setConverter(attacker)")
sim(TP, "setReceivers(address,address,address)", enc_addr(ATTACKER)*3, "setReceivers(attacker x3)")
sim(TP, "dispatch()", "", "dispatch()  [keeper]")
sim(TP, "processBondingCurveTax(uint256)", enc_uint(1), "processBondingCurveTax(1)")

print("\n--- Dividend", DIV, "(holds XAUt for holders) ---")
sim(DIV, "emergencyWithdraw(address,uint256,address)", enc_addr(X)+enc_uint(0)+enc_addr(ATTACKER), "emergencyWithdraw(XAUt, all -> attacker)")
sim(DIV, "setShare(address,uint256)", enc_addr(ATTACKER)+enc_uint(10**24), "setShare(attacker, huge)")
sim(DIV, "excludeAddress(address)", enc_addr(ATTACKER), "excludeAddress(attacker)")
sim(DIV, "setDividendToken(address)", enc_addr(ATTACKER), "setDividendToken(attacker)")
sim(DIV, "distributeDividend(address[])", enc_uint(32)+enc_uint(0), "distributeDividend([])  [keeper]")
sim(DIV, "withdrawDividends()", "", "withdrawDividends()  [self-claim]")

print("\n--- Token", T, "(ownership renounced) ---")
sim(T, "startMigration()", "", "startMigration()")
sim(T, "finalizeMigration()", "", "finalizeMigration()")

print("\n" + "="*90)
print("LIVE STATE")
print("="*90)
def bal(tok, who, dec, name):
    v = read_uint(tok, "balanceOf(address)", [who])
    print(f"  {name:42} {v/10**dec:.6f}  (raw {v})")
    return v

print("\n--- PancakePair CETS/XAUt", PAIR, "---")
ok,res = call_or_revert(PAIR, selector("getReserves()"))
if ok:
    h=res[2:]; r0=int(h[0:64],16); r1=int(h[64:128],16); ts=int(h[128:192],16)
    print(f"  reserve0 (XAUt, 6dec): {r0/1e6}")
    print(f"  reserve1 (CETS,18dec): {r1/1e18}")
    print(f"  blockTimestampLast: {ts}")
print("  token0:", read_addr(PAIR,"token0()"), "token1:", read_addr(PAIR,"token1()"))
print("  pair totalSupply(LP):", read_uint(PAIR,"totalSupply()")/1e18)
print("  kLast:", read_uint(PAIR,"kLast()"))

print("\n--- XAUt (6 dec) balances held on behalf of holders ---")
bal(X, TP, 6, "XAUt held by TaxProcessor")
bal(X, DIV, 6, "XAUt held by Dividend")
bal(X, PAIR, 6, "XAUt in pool (reserve check)")

print("\n--- CETS (18 dec) balances ---")
bal(T, PAIR, 18, "CETS in pool")
bal(T, T, 18, "CETS accrued as tax on token itself")
bal(T, TP, 18, "CETS held by TaxProcessor")
bal(T, DIV, 18, "CETS held by Dividend")
bal(T, "0x000000000000000000000000000000000000dEaD", 18, "CETS burned (dead)")

print("\n--- Token poolState (tax config) ---")
ok,res=call_or_revert(T, selector("getPoolStateData()"))
if ok:
    h=res[2:]
    st=int(h[0:64],16); buy=int(h[64:128],16); sell=int(h[128:192],16)
    lt=int(h[192:256],16); te=int(h[256:320],16); afe=int(h[320:384],16)
    states=["BondingCurve","Migrating","TaxEnforcedAntiFarmer","TaxEnforced","TaxFree"]
    print(f"  state: {st} ({states[st] if st<len(states) else '?'})")
    print(f"  buyTaxRate: {buy} bps ({buy/100}%)   sellTaxRate: {sell} bps ({sell/100}%)")
    print(f"  liquidationThreshold: {lt/1e18} CETS")
    print(f"  taxExpirationTime: {te}   antiFarmerExpirationTime: {afe}")

print("\n--- pools mapping membership ---")
for name,a in [("mainPool",PAIR)]:
    print(f"  pools[{name}]:", read_bool(T,"pools(address)",[a]))

print("\n--- Standing approvals (allowance) ---")
print("  CETS allowance TaxProcessor->router:", read_uint(T,"allowance(address,address)",[TP,ROUTER])/1e18)
print("  XAUt allowance TaxProcessor->router:", read_uint(X,"allowance(address,address)",[TP,ROUTER])/1e6)
print("  CETS allowance token->TaxProcessor  :", read_uint(T,"allowance(address,address)",[T,TP])/1e18, "(self-approve for pulls)")

print("\n--- Dividend accounting ---")
print("  totalShares:", read_uint(DIV,"totalShares()")/1e18)
print("  minimumShareBalance:", read_uint(DIV,"minimumShareBalance()")/1e18)
