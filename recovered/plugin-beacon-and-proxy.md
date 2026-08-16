# Plugin Beacon (#3) + Plugin Proxy shell (#4) — confirmation & authority

Two standard OpenZeppelin proxy-pattern contracts on the main HYDX/USDC Algebra pool
(`pool = 0x51f0b932855986b0e621c9d4db6eee1f4644d3d2`, READ from plugin `pool()`).

> READ = observed on-chain (bytecode selectors, strings, storage, `eth_call`) or from verified source.
> INFERRED = deduced. Both contracts below match standard OZ bytecode and are treated as confirmed.

---

## #3 — UpgradeableBeacon `0x106937fc03212a762be17d529893a32e47ba13a1`

**Runtime size:** 807 bytes.

**CONFIRMED standard OZ `UpgradeableBeacon` (READ):**
- Dispatcher selectors are exactly: `upgradeTo(address)` `0x3659cfe6`, `implementation()` `0x5c60da1b`,
  `owner()` `0x8da5cb5b`, `renounceOwnership()` `0x715018a6`, `transferOwnership(address)` `0xf2fde38b`
  — the entire `UpgradeableBeacon` + `Ownable` surface, nothing else.
- Embedded revert strings: `"UpgradeableBeacon: implementation is not a contract"`,
  `"Ownable: caller is not the owner"`, `"Ownable: new owner is the zero address"`.

**Live values (READ via `eth_call`):**
- `implementation()` = **`0xaf11628e68e8bd45375560e549ab8411fa034d4f`** (the VERIFIED
  `AlgebraUpgradeablePlugin` impl) ✔ matches expectation.
- `owner()` = **`0xa8dd4c05796801c734e99d5582e90e3a8bd88194`**.

**Who can swap the plugin logic on the live pool (READ + verified factory source):**
- `upgradeTo` is `onlyOwner`, and `owner()` = **`0xa8dd4c05…`**, which is the
  **`AlgebraUpgradeablePluginFactory` behind a TransparentUpgradeableProxy** (READ: its EIP-1967 impl
  slot = `0xde57c7d4…ae922` = the verified factory impl; `beacon()` on it returns `0x106937…`).
  So the beacon's owner is a *contract*, not an EOA — the plugin can only be upgraded **through the
  factory**.
- In the verified factory source
  (`contracts/liquidity/AlgebraUpgradeablePlugin_0xaf114d4f/contracts/AlgebraUpgradeablePluginFactory.sol`):
  ```
  function upgradePlugins(address newImplementation) external onlyAdministrator {
      UpgradeableBeacon(_getStorage().beacon).upgradeTo(newImplementation);
  }
  modifier onlyAdministrator() {
      require(IAlgebraFactory(algebraFactory)
              .hasRoleOrOwner(ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR, msg.sender));
  }
  ```
  **=> Effective authority to change plugin logic on the pool = any holder of the
  `ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR` role on the AlgebraFactory
  (`0x36077d39cdc65e1e3fb65810430e5b2c4d5fa29e`), or the AlgebraFactory owner.**
- **Second, lower-level lever:** the factory *itself* is a TransparentUpgradeableProxy whose admin is
  ProxyAdmin **`0x2689ef6a746f1b253cd772fb045a7563505bed00`** (1,650 bytes), and that ProxyAdmin's
  `owner()` = **`0x74266f2b206d1359b83fc74949ef07176fb3ae03`** (READ: an **EOA**, no code). That EOA
  can replace the whole factory implementation and thereby the upgrade logic. It is the Hydrex-side
  governance key and is **distinct** from the MevX EIP-7702 key `0x000000077ac1`.

**Bottom line #3:** Standard OZ `UpgradeableBeacon`, pointing at the verified plugin impl, owner =
plugin factory `0xa8dd4c05`. Plugin-logic upgrades are gated by the factory's
`ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR` role (on AlgebraFactory `0x36077d39`); the factory itself
is replaceable by EOA `0x74266f2b` via ProxyAdmin `0x2689ef6a`.

---

## #4 — Plugin proxy shell `0xe33a242990780ab872ae986ad68206478fc85ae1`

**Runtime size:** 405 bytes.

**CONFIRMED standard OZ `BeaconProxy` (`AlgebraPluginProxy`) (READ):**
- No function dispatcher of its own — pure fallback that reads the beacon and delegatecalls (the one
  PUSH4 seen in a naive scan is not a real selector branch; every call including `pool()` is served by
  delegatecall to the impl). Size 405 bytes is the standard `BeaconProxy` footprint.
- EIP-1967 **beacon slot** (`0xa3f0…133d50`) = **`0x106937fc03212a762be17d529893a32e47ba13a1`** ✔ →
  points at beacon #3.
- Therefore its live logic = beacon.implementation() = `0xaf11628e…` (verified plugin).

**READ live:** `pool()` (delegated to impl) = `0x51f0b932…d3d2` — this proxy is the plugin instance
attached to the main HYDX/USDC pool. Its ERC-7201 MevX storage was read here:
`mevxRouter=0xb32f98`, `mevxExecutor=0x3a9808`, `mevxProfitDistributor=0x53c67db9`, `mevxConfigId=0x0`.

**Who controls it:** it has no admin of its own — it always tracks whatever impl beacon #3 holds. So
control over `0xe33a24`'s behavior = control over beacon #3 (see above). **No separate upgrade key.**

**Bottom line #4:** Standard OZ `BeaconProxy` → beacon `0x106937` → verified plugin `0xaf11628e`.
Confirmed; no independent authority.

---

## Authority map (READ)

```
MAIN POOL 0x51f0…d3d2
  └─ plugin proxy (#4) 0xe33a24  [BeaconProxy]
        └─ beacon (#3) 0x106937  [UpgradeableBeacon]  owner = factory 0xa8dd4c05
              └─ impl 0xaf11628e  [VERIFIED AlgebraUpgradeablePlugin]
                    ├─ mevxRouter   = 0xb32f98 (Transparent proxy → impl 0x2c3bae, UNVERIFIED)
                    ├─ mevxExecutor = 0x3a9808 (Transparent proxy → impl 0x9e9046, UNVERIFIED)
                    └─ profitDistrib = 0x53c67db9 (Transparent proxy, owner 0x000000077ac1)

Plugin-logic upgrade authority (Hydrex side):
  factory 0xa8dd4c05 (AlgebraUpgradeablePluginFactory, Transparent proxy)
     · upgradePlugins() gated by ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR on AlgebraFactory 0x36077d39
     · factory impl replaceable by ProxyAdmin 0x2689ef6a  →  owner EOA 0x74266f2b

MevX contracts upgrade + owner authority (MevX side):
  ProxyAdmin 0x0a70fa8e  (upgrades executor 0x3a9808 AND router 0xb32f98)
     └─ owner = 0x000000077ac1  ← EIP-7702 EOA, code 0xef0100 63c0c19a…  (delegate 0x63c0c19a)
  router.owner() = profitDistributor.owner() = 0x000000077ac1  (same key)
```

**Key separation:** the **MevX plugin infrastructure** (router/executor/distributor logic + upgrades)
is controlled by a **single EIP-7702-delegated EOA `0x000000077ac1`**, while **which plugin runs on
the pool** is controlled by the **Hydrex/Algebra factory governance** (role on AlgebraFactory
`0x36077d39`; factory replaceable by EOA `0x74266f2b`). Both are single-key (no on-chain
multisig/timelock observed at the immediate owner level) — a centralization point worth flagging.
