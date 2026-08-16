# Shared-Library Integrity Report — Hydrex (HYDX) on Base

Purpose: verify that the project's **copies** of well-known shared libraries (OpenZeppelin,
Gnosis Safe, Algebra Integral, Solidly-family) inside this Etherscan-extracted audit repo are
byte-identical to the **real upstream originals** fetched fresh from npm (unpkg) / GitHub — so a
diff-based audit is not blinded by a doctored baseline.

Method: for each file, the exact upstream version was determined (OZ `last updated vX.Y.Z` header
markers, Safe `VERSION` constant, Algebra tag/npm md5-matching), the original was fetched from
`unpkg.com` / `raw.githubusercontent.com` (never from another copy inside this repo), and compared
with `diff` after CRLF normalization (`sed 's/\r$//'`). Trivial header/pragma/whitespace deltas are
**not** treated as findings; changes to logic, modifiers, access checks, constants, or arithmetic
**are**.

**Bottom line:** Of the authority/value-path files checked, **all are byte-identical to their stated
upstream** except **one** — a benign, self-documented constructor addition in a project-relocated
`ProxyAdmin.sol`. No silent modification to any ERC20, access-control, signature, proxy-authority,
Safe, or Algebra pool-core logic was found.

---

## ⚠️ MODIFIED FINDINGS (read first)

### 1. `ProxyAdmin.sol` — added initial-owner constructor (BENIGN, documented)

- **File:** `contracts/governance/ProxyAdmin_0x6e25ad40/contracts/proxy/ProxyAdmin.sol`
- **Upstream:** OpenZeppelin `@4.8.3` `proxy/transparent/ProxyAdmin.sol`
- **Diff:** `integrity/diffs/ProxyAdmin.diff`
- **Verdict:** MODIFIED — but assessed **benign**. The contract adds a constructor that lets the
  deployer set the initial owner explicitly instead of defaulting to `msg.sender`. It is
  self-annotated ("ADDED by DeFiFoFum to set initial owner"), a well-known pattern. **All four
  authority functions — `changeProxyAdmin`, `upgrade`, `upgradeAndCall` (and getters) — retain their
  original `onlyOwner` gating unchanged.** No access check was weakened and no backdoor was added.

```diff
6,7c6,7
< import "./TransparentUpgradeableProxy.sol";
< import "../../access/Ownable.sol";
---
> import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
> import "@openzeppelin/contracts/access/Ownable.sol";
11a12
>  * @notice Added constructor to set initial owner
13a15,19
>     /// @dev ADDED by DeFiFoFum to set initial owner
>     constructor(address _initialOwner) Ownable() {
>         _transferOwnership(_initialOwner);
>     }
>
```

> Note: this ProxyAdmin is the admin of the project's TransparentUpgradeableProxies. The
> modification only affects *how the initial owner is assigned at deploy time*; the ongoing
> access control on upgrades is stock OZ. Auditors should still confirm **who** the owner is
> on-chain, but the code path itself is not tampered.

**No other MODIFIED findings.** Everything below is IDENTICAL, a benign non-logic diff, or a
bespoke fork with no clean upstream.

---

## OpenZeppelin — HydrexToken (target token), OZ **v5.3.0**, pragma ^0.8.27 (compiled 0.8.28)

Dir: `contracts/target/HydrexToken_0x00006b30/node_modules/@openzeppelin/contracts/`
Version confirmed: ERC20.sol + EIP712.sol byte-identical to v5.3.0 (highest `last updated` marker).

| File | Upstream | Verdict | Note |
|---|---|---|---|
| token/ERC20/ERC20.sol | OZ 5.3.0 | **IDENTICAL** | core transfer/mint/burn/allowance logic unchanged |
| token/ERC20/extensions/ERC20Burnable.sol | OZ 5.3.0 | **IDENTICAL** | |
| token/ERC20/extensions/ERC20Permit.sol | OZ 5.3.0 | **IDENTICAL** | EIP-2612 permit unchanged |
| access/Ownable.sol | OZ 5.3.0 | **IDENTICAL** | |
| utils/cryptography/ECDSA.sol | OZ 5.3.0 | **IDENTICAL** | signature recovery / malleability guard unchanged |
| utils/cryptography/EIP712.sol | OZ 5.3.0 | **IDENTICAL** | domain separator unchanged |
| utils/Nonces.sol | OZ 5.3.0 | **IDENTICAL** | permit nonce source unchanged |
| utils/cryptography/MessageHashUtils.sol | OZ 5.3.0 | **IDENTICAL** | |
| utils/ShortStrings.sol | OZ 5.3.0 | **IDENTICAL** | |

*(The token contract `contracts/HydrexToken.sol` itself is project code, not a shared library — out
of scope for this integrity check; its OZ parents above are verified clean.)*

## OpenZeppelin — access / proxy / reentrancy (OZ **v4.9.x**, package 4.9.6)

These extractions are independent from the token's OZ 5.x tree; each file diffed against the version
in its own `last updated` marker.

| File (dir) | Upstream | Verdict | Note |
|---|---|---|---|
| **ProxyAdmin.sol** (ProxyAdmin_0x6e25ad40) | OZ 4.8.3 | **MODIFIED (benign)** | added initial-owner constructor — see top |
| proxy/transparent/TransparentUpgradeableProxy.sol (ProxyAdmin) | OZ 4.9.0 | **IDENTICAL** | admin-gated upgrade logic unchanged; 5 runtime copies across repo share identical bytes |
| proxy/ERC1967/ERC1967Proxy.sol (ProxyAdmin) | OZ 4.7.0 | **IDENTICAL** | |
| proxy/ERC1967/ERC1967Upgrade.sol (ProxyAdmin) | OZ 4.9.0 | **IDENTICAL** | slot/upgrade internals unchanged |
| proxy/Proxy.sol (ProxyAdmin) | OZ 4.6.0 | **IDENTICAL** | |
| utils/Address.sol (ProxyAdmin) | OZ 4.9.0 | **IDENTICAL** | |
| utils/StorageSlot.sol (ProxyAdmin) | OZ 4.9.0 | **IDENTICAL** | |
| access/Ownable.sol (ProxyAdmin) | OZ 4.9.0 | **IDENTICAL** | |
| utils/Context.sol (ProxyAdmin) | OZ 4.9.4 | **IDENTICAL** | |
| access/AccessControlEnumerable.sol (OptionTokenV4) | OZ 4.5.0 | **IDENTICAL** | role enumeration unchanged |
| access/AccessControl.sol (OptionTokenV4) | OZ 4.9.0 | **IDENTICAL** | `onlyRole` / grant/revoke unchanged |
| access/IAccessControl.sol (OptionTokenV4) | OZ 4.4.1 | **IDENTICAL** | |
| access/IAccessControlEnumerable.sol (OptionTokenV4) | OZ 4.4.1 | **IDENTICAL** | |
| utils/structs/EnumerableSet.sol (OptionTokenV4) | OZ 4.9.0 | **IDENTICAL** | backing store for role members unchanged |
| token/ERC20/utils/SafeERC20.sol (OptionTokenV4) | OZ 4.9.3 | **IDENTICAL** | |
| governance/TimelockController.sol (TimelockControllerEnumerable) | OZ 4.9.0 | **IDENTICAL** | delay/schedule/execute + role logic unchanged |
| access/AccessControl.sol (Timelock) | OZ 4.9.0 | **IDENTICAL** | |
| access/AccessControlEnumerable.sol (Timelock) | OZ 4.5.0 | **IDENTICAL** | |
| utils/structs/EnumerableSet.sol (Timelock) | OZ 4.9.0 | **IDENTICAL** | |
| proxy/beacon/BeaconProxy.sol (BeaconProxy ×4 dirs) | OZ 4.7.0 | **IDENTICAL** | all 4 copies byte-identical to each other + upstream |
| security/ReentrancyGuard.sol (AlgebraFactory) | OZ 4.9.0 | **IDENTICAL** | non-upgradeable guard |
| contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol (×7 dirs) | OZ-upgradeable 4.9.6 | **IDENTICAL** | all 7 copies identical; see benign note below |
| access/Ownable.sol + utils/Address.sol + proxy/beacon/IBeacon.sol (UpgradeableBeaconForFactory) | OZ 4.9.0 / 4.4.1 | **IDENTICAL** | authority base for the custom beacon |

**Benign non-logic note — ReentrancyGuardUpgradeable.sol** (`integrity/diffs/ReentrancyGuardUpgradeable.diff`):
vs OZ-upgradeable 4.9.0 the only delta is a named-import style change
(`import {Initializable} from "../proxy/utils/Initializable.sol";`). Re-checked against 4.9.6 →
**IDENTICAL**. The delta was an upstream version bump, not a repo edit. No logic change.

### Project-custom contracts (no OZ upstream — bespoke, reviewed for gating)

| File | Verdict | Note |
|---|---|---|
| governance/.../TimelockControllerEnumerable.sol | NO-UPSTREAM (project) | thin `TimelockController`+`AccessControlEnumerable` multiple-inheritance wrapper; parents verified IDENTICAL |
| liquidity/.../UpgradeableBeaconForFactory.sol | NO-UPSTREAM (project) | explicitly bespoke ("OZ's UpgradeableBeacon didn't quite work"); `upgradeTo` is `onlyOwner`, validates implementation is a contract — gating sound |
| .../hardhat-dependency-compiler/.../TransparentUpgradeableProxy.sol | NO-UPSTREAM (build stub) | 3-line file that just `import`s the real OZ file (verified IDENTICAL); harmless build artifact |

## Gnosis Safe — governance singletons

| File | Upstream | Verdict | Note |
|---|---|---|---|
| **GnosisSafeL2_0xfb1b91ea** (VERSION = 1.3.0) | | | `@gnosis.pm/safe-contracts@1.3.0` |
| contracts/GnosisSafe.sol | Safe 1.3.0 | **IDENTICAL** | `execTransaction` / `checkSignatures` / threshold unchanged |
| contracts/GnosisSafeL2.sol | Safe 1.3.0 | **IDENTICAL** | |
| contracts/base/OwnerManager.sol | Safe 1.3.0 | **IDENTICAL** | owner add/remove/swap + threshold unchanged |
| contracts/base/ModuleManager.sol | Safe 1.3.0 | **IDENTICAL** | module exec path (sig-bypass surface) unchanged |
| contracts/base/Executor.sol | Safe 1.3.0 | **IDENTICAL** | |
| contracts/base/GuardManager.sol | Safe 1.3.0 | **IDENTICAL** | |
| contracts/common/SignatureDecoder.sol | Safe 1.3.0 | **IDENTICAL** | |
| **SafeL2_0x29fcc762** (VERSION = 1.4.1) | | | `@safe-global/safe-contracts@1.4.1` |
| contracts/Safe.sol | Safe 1.4.1 | **IDENTICAL** | `execTransaction` / `checkSignatures` / threshold unchanged |
| contracts/SafeL2.sol | Safe 1.4.1 | **IDENTICAL** | |
| contracts/base/OwnerManager.sol | Safe 1.4.1 | **IDENTICAL** | |
| contracts/base/ModuleManager.sol | Safe 1.4.1 | **IDENTICAL** | |
| contracts/base/Executor.sol | Safe 1.4.1 | **IDENTICAL** | |
| contracts/base/GuardManager.sol | Safe 1.4.1 | **IDENTICAL** | |
| contracts/base/FallbackManager.sol | Safe 1.4.1 | **IDENTICAL** | |
| contracts/common/SignatureDecoder.sol | Safe 1.4.1 | **IDENTICAL** | |

## Algebra Integral core — main pool `AlgebraPool_0x51f0d3d2`

Version pinned by md5-matching: **pool core = tag `v1.2.1-integral`** (GitHub `cryptoalgebra/Algebra`,
`src/core/contracts/`); **libraries = `@cryptoalgebra/integral-core@1.2.10`** on npm (library set is
stable across 1.2.x). pragma =0.8.20.

| File | Upstream | Verdict | Note |
|---|---|---|---|
| contracts/AlgebraPool.sol | v1.2.1-integral | **IDENTICAL** | mint/burn/swap/flash entrypoints unchanged |
| contracts/base/AlgebraPoolBase.sol | v1.2.1-integral | **IDENTICAL** | |
| contracts/base/Positions.sol | v1.2.1-integral | **IDENTICAL** | fee-growth / position accounting unchanged |
| contracts/base/SwapCalculation.sol | v1.2.1-integral | **IDENTICAL** | swap step math unchanged |
| contracts/base/ReservesManager.sol | v1.2.1-integral | **IDENTICAL** | |
| contracts/base/TickStructure.sol | v1.2.1-integral | **IDENTICAL** | |
| contracts/base/ReentrancyGuard.sol | v1.2.1-integral | **IDENTICAL** | Algebra's own guard (not OZ) |
| contracts/base/common/Timestamp.sol | v1.2.1-integral | **IDENTICAL** | |
| libraries/TickMath.sol | integral-core 1.2.10 | **IDENTICAL** | |
| libraries/PriceMovementMath.sol | integral-core 1.2.10 | **IDENTICAL** | core price-movement arithmetic unchanged |
| libraries/LiquidityMath.sol | integral-core 1.2.10 | **IDENTICAL** | |
| libraries/TickManagement.sol | integral-core 1.2.10 | **IDENTICAL** | |
| libraries/FullMath.sol | integral-core 1.2.10 | **IDENTICAL** | |
| libraries/LowGasSafeMath.sol | integral-core 1.2.10 | **IDENTICAL** | |
| libraries/SafeCast.sol | integral-core 1.2.10 | **IDENTICAL** | |
| libraries/TokenDeltaMath.sol | integral-core 1.2.10 | **IDENTICAL** | |
| libraries/TickTree.sol | integral-core 1.2.10 | **IDENTICAL** | |
| libraries/Constants.sol | integral-core 1.2.10 | **IDENTICAL** | fee caps / constants unchanged |
| libraries/Plugins.sol | integral-core 1.2.10 | **IDENTICAL** | |
| libraries/SafeTransfer.sol | integral-core 1.2.10 | **IDENTICAL** | |

## Solidly-family (Pair / BribeV2) — bespoke, best-effort

| File | Upstream | Verdict | Note |
|---|---|---|---|
| liquidity/Pair_0x605a2e1d/contracts/Pair.sol | none clean | **NO-UPSTREAM-FOUND** | Solidly/Thena-family fork, pragma 0.8.13, customized (Dibs referral `IDibs`; "2024-10 immutable removed for deterministic deployment"). Value-critical logic spot-checked: `_k` invariant is canonical Solidly (`x³y+y³x ≥ k` stable / `xy ≥ k` volatile); swap enforces `k_after ≥ k_before`; `Math.sqrt` is standard Babylonian. No tampering seen in the invariant/swap path, but no byte-identical upstream exists. |
| liquidity/BribeV2_0x6225a28d/contracts/VoterV5/BribeV2.sol | none clean | **NO-UPSTREAM-FOUND** | bespoke Hydrex `VoterV5` bribe contract; its OZ `ReentrancyGuardUpgradeable` dep verified IDENTICAL (above). Core logic not line-reviewed (out of shared-library scope). |

---

## Coverage & honesty notes

**"IDENTICAL" verdicts above cover only the specific files listed and diffed.** They do not certify
any file not named here, nor the project's own contracts.

Checked (per library):
- **OpenZeppelin 5.3.0 (token):** 9 logic/authority files — all IDENTICAL.
- **OpenZeppelin 4.9.x (access/proxy/reentrancy):** ~24 files across OptionTokenV4, ProxyAdmin,
  TimelockControllerEnumerable, BeaconProxy (×4), TransparentUpgradeableProxy (×5), AlgebraFactory,
  and 7 ReentrancyGuardUpgradeable copies — all IDENTICAL except the one benign ProxyAdmin
  constructor addition.
- **Gnosis Safe:** 7 core files @1.3.0 + 8 core files @1.4.1 — all IDENTICAL.
- **Algebra Integral:** 8 pool-core files @v1.2.1-integral + 12 libraries @1.2.10 — all IDENTICAL.
- **Solidly-family:** Pair + BribeV2 — no clean upstream (bespoke); Pair invariant/swap spot-reviewed, no tampering.

**Not covered / not reached (lower priority — no logic, or out of shared-library scope):**
- Pure interface/`I*.sol` files and small utils not carrying authority logic (e.g. token dir
  `Strings`, `Math`, `SignedMath`, `SafeCast`, `Panic`, `StorageSlot`; Safe peripheral files
  `MultiSend*`, `CreateCall`, `SignMessageLib`, `CompatibilityFallbackHandler`,
  `GnosisSafeProxyFactory`, `StorageAccessible`; Algebra pool interfaces) were not individually
  diffed. Priority was on files that carry logic, modifiers, access checks, constants, or arithmetic.
- Other contract categories outside the priority list (e.g. `mint-authority/MinterUpgradeableV4`,
  `ve-core/VotingEscrowV2Upgradeable`, `ve-core/VoterV5`, `options/OptionTokenV4` project logic,
  `external/*`) were only touched for their shared OZ `ReentrancyGuardUpgradeable` dependency.
- BribeV2 and the Solidly Pair core business logic were not line-by-line reviewed (bespoke, no
  upstream to diff).

Upstream sources used: `unpkg.com/@openzeppelin/contracts@<ver>`,
`unpkg.com/@openzeppelin/contracts-upgradeable@<ver>`, `unpkg.com/@gnosis.pm/safe-contracts@1.3.0`,
`unpkg.com/@safe-global/safe-contracts@1.4.1`, `unpkg.com/@cryptoalgebra/integral-core@1.2.10`,
`raw.githubusercontent.com/cryptoalgebra/Algebra/v1.2.1-integral`. All comparisons CRLF-normalized.

Recorded diffs: `integrity/diffs/ProxyAdmin.diff` (the modification),
`integrity/diffs/ReentrancyGuardUpgradeable.diff` (benign import-style, resolved to IDENTICAL @4.9.6).
