# Integrity report — are the surroundings what they appear to be?

The bespoke Flap code is read directly in `contracts/`. This report checks the
*shared building blocks* it sits on, against **genuine upstream** (fetched live from
the real source repos), not against a copy that shipped with the project — because a
doctored baseline is what makes a diff-based review blind.

## 1. Bundled OpenZeppelin — byte-identical to upstream v4.9.4 ✅

Every `*.sol` file under an `openzeppelin*` path in each bespoke contract was
diffed, byte-for-byte (line-endings normalized), against the OpenZeppelin GitHub
release tags. Reproduce with `tools/integrity.py`; raw results in
[`_oz_diff_raw.json`](./_oz_diff_raw.json).

| Contract | OZ files | Result |
|---|---|---|
| `FlapTaxTokenV3_impl` (the token logic) | 20 | **20/20 MATCH** |
| `TaxProcessorUniV2_impl` (holds funds) | 11 | **11/11 MATCH** |
| `Dividend_impl` (holds funds) | 9 | **9/9 MATCH** |
| `Portal_impl` (launchpad authority) | 22 | **22/22 MATCH** |

**62/62 bundled OpenZeppelin files are genuine v4.9.4.** In particular
`OwnableUpgradeable`, `ERC20Upgradeable`, `ERC20PermitUpgradeable`,
`ReentrancyGuardUpgradeable`, `Initializable`, `ContextUpgradeable`, and
`EIP712Upgradeable` — the files where a hidden owner, silent mint, or spoofed
`_msgSender` would live — are unmodified. No doctored baseline.

> Method note: OZ per-file headers say "last updated vX"; a file "last updated
> v4.9.0" is byte-identical across the 4.9.x patch line. The checker tries the whole
> 4.9.x range and marks MATCH on the first exact hit, so a stale "last updated"
> header does not create a false DIFF.

## 2. Bundled Solady — byte-identical to upstream v0.0.201 ✅

The Portal bundles two Solady files; both match genuine Solady:

| File | Result |
|---|---|
| `lib/solady/src/utils/FixedPointMathLib.sol` | **MATCH** solady v0.0.201 |
| `lib/solady/src/utils/SSTORE2.sol` | **MATCH** solady v0.0.201 |

## 3. The CETS/XAUt pool is a genuine PancakeSwap V2 pair — cryptographic proof ✅

Rather than trust the verified `PancakePair` label, the pool address was derived
from first principles:

```
CREATE2(
  deployer   = PancakeFactory 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73,
  salt       = keccak256(token0 ‖ token1) = keccak256(XAUt ‖ CETS),
  initHash   = 0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5   (canonical PancakeSwap V2 pair init-code hash)
) = 0xdabbd019c0174BDAE6354f32b158D42e4A0E7489
```

This **equals the on-chain `mainPool`**, and `factory.getPair(XAUt,CETS)` returns
the same address, and `pair.factory()` returns the canonical factory. Because the
address is fully determined by the init-code hash, the pool necessarily runs the
**unmodified canonical PancakePair bytecode** — it cannot be a lookalike with
altered swap/skim logic.

## 4. Canonical infrastructure addresses — all match well-known deployments ✅

| Contract | Address in this system | Identity |
|---|---|---|
| PancakeSwap V2 Router | `0x10ED43C718714eb63d5aA57B78B54704E256024E` | canonical PancakeRouter (verified) |
| PancakeSwap V2 Factory | `0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73` | canonical PancakeFactory (verified) |
| WBNB | `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c` | canonical WBNB (verified) |
| Safe singleton (launchpad Safe) | `0x29fcB43b46531BcA003ddC8FCB67FFE91900C762` | canonical `SafeL2` v1.4.1 (verified) |
| Safe singleton (fee-receiver Safe) | `0x3E5c63644E683549055b9Be8653de26E0B4CD36E` | canonical `GnosisSafeL2` v1.3.0 (verified) |

Both multisigs run canonical Safe singleton logic; only their owner sets / thresholds
are project-specific (captured in live-state).

## 5. XAUt (quote asset) identity

`0x21cAef8A43163Eea865baeE23b9C2E327696A3bf` is a `TransparentUpgradeableProxy` whose
implementation is the verified `TetherTokenOFTExtension`, reporting `name()="Tether
Gold"`, `symbol()="XAUt"`, `decimals()=6`. This is the real Tether Gold OFT on BSC,
not a thin lookalike. Its implementation is **upgradeable by Tether's own admin**
(`0xedaba0…B027`) — an authority external to this project but sitting under the value
(recorded in `UNRESOLVED.md`).

## Bottom line

Every shared building block the CETS system rests on — OpenZeppelin, Solady, the
PancakeSwap pair/router/factory, WBNB, the Safe singletons — is genuine and
unmodified. A diff-based audit of the bespoke Flap code can therefore trust its
baseline. The only unverified byte in the graph is the SwapRegistry implementation
(off CETS's active path; behavior recovered in `recovered-behavior/`).
