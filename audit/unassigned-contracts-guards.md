# Entry-point guards — contracts not assigned to a subsystem deep-dive

These four in-scope contracts carry no material value flow or their guards are trivial; verified directly
here so the enumeration has complete coverage. READ from source (file:line) + live where noted.

## HydrexToken `0x00000e7e…` (target) — 10 state-changing entry points
Standard OpenZeppelin ERC20 + Permit + Burnable + Ownable (integrity: byte-identical to OZ v5.3.0).
| fn | guard | why not exploitable |
|---|---|---|
| `transfer`,`transferFrom`,`approve`,`increase/decreaseAllowance` | standard ERC20 allowance | no custom logic; no hooks/fee/blacklist |
| `permit` | EIP-2612 sig over `nonces`+`deadline` | standard OZ ECDSA; nonce prevents replay |
| `burn`,`burnFrom` | burns caller's own / allowance-checked | ERC20Burnable stock |
| `mint(to,amount)`,`initialMint(recipient)` | `onlyOwner` (= Minter `0xa7d6`) | unprivileged caller reverts (verified live: `mint` from 0xdEaD reverts); `initialMinted=true` already |
| `transferOwnership`,`renounceOwnership` | `onlyOwner` | reverts for non-owner (verified live) |

## PoolEligibilityOracle `0xc98f…` (proxy) — 7 state-changing
| fn | guard | why not exploitable |
|---|---|---|
| `setPoolEligibility(pool,bool)` | `msg.sender==oracleUpdater‖owner()` (`PoolEligibilityOracle.sol:55`) | only marks a pool eligible for *permissionless gauge creation*; worst case = emission misdirection (GAUGE_ADMIN bypasses this anyway). Not a value path. |
| `setBatchPoolEligibility` | same | same |
| `setGovernanceOverride`,`setOracleUpdater` | `onlyOwner` (`:69,:76`) | non-owner reverts |
| `initialize` | OZ `initializer` (`:37`) | already initialized ⇒ re-call reverts |
| `transfer/renounceOwnership` | `onlyOwner` | — |

## AlgebraCustomPoolEntryPoint `0x00ede…` (POOLS_ADMINISTRATOR holder) — 7 state-changing
Holds `POOLS_ADMINISTRATOR` on the factory, but its own setters are gated so they only reach **custom
pools this caller deployed**, never the main default HYDX/USDC pool.
| fn | guard | why not exploitable |
|---|---|---|
| `createCustomPool` | `msg.sender==deployer` (`:33`) | only the configured deployer |
| `beforeCreatePoolHook`,`beforeCreateCustomPool` | `msg.sender==factory` (`:47,:55`) | only the factory |
| `setTickSpacing`,`setPlugin`,`setPluginConfig`,`setFee` | `onlyCustomDeployer(pool)` → `pool==factory.customPoolByPair(msg.sender,token0,token1)` (`:86`) | **the main pool `0x51f0` is a *default* pool, not a custom pool, so this equality can never hold for it** — this contract cannot administer the main pool. Confirmed in `../live-state/liquidity-analysis.md`. |

## VeArtProxy `0x7cba…` (proxy) — 3 state-changing
`initialize(string)` (initializer), `transferOwnership`/`renounceOwnership` (onlyOwner). Pure `tokenURI`
art rendering for veNFTs; holds/moves no value. Not a value or authority path.

## Upstream/infra (covered elsewhere, not re-enumerated here)
- **AlgebraPool / AlgebraFactory / AlgebraPoolDeployer** — pool core byte-identical to Algebra Integral
  v1.2.1 (`../integrity/`); admin surface + "no principal-drain path" analysis in
  `../live-state/liquidity-analysis.md` (all setters `_checkIfAdministrator` = factory owner / POOLS_ADMIN).
- **AlgebraUpgradeablePlugin (+ Farming/ALM/MevX modules)** — hooks are `onlyPool`, set fee or revert, no
  reserve-moving path (`../live-state/liquidity-analysis.md`); MevX executor/router recovered in `../recovered/`
  (executor has permissionless `executeRoute`/`receiveFlashLoan` — see FINDINGS for the fund-less caveat).
- **OZ / Gnosis Safe / Timelock / ProxyAdmin / USDC** — standard, integrity-checked; privileged surfaces
  out of the unprivileged-attacker scope.
