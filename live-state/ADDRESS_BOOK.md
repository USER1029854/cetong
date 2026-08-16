# Hydrex (HYDX) trust-graph address book


Total nodes: 79


## target
- `0x00000e7efa313f4e11bfff432471ed9423ac6b30` **HydrexToken** (verified) — HydrexToken (HYDX) - the audit target

## mint-authority
- `0xa7d64625f45548a19b2a19e28e7546bb2839003e` **MinterUpgradeableV3Proxy** (verified) [proxy→0xde973c9d…] — MinterUpgradeableV3Proxy - token owner, can mint HYDX
- `0xde973c9d1afee6c5a64c0a0a835d269954f4d219` **MinterUpgradeableV4** (verified) — MinterUpgradeableV4 - Minter implementation
- `0x5aaa65af617fa50041325f46ecee5613aaff2727` **RevisedPhasedEmissionSchedule** (verified) — EmissionSchedule - bounds weekly mint

## ve-core
- `0x25f4d95ae6734b517675cbe863cf91879964b970` **BribeFactoryV4** (verified) — BribeFactoryV4 implementation
- `0x58b4f302753003ffc1d70791775b93d0edc87dc1` **BribeFactoryV4Proxy** (verified) [proxy→0x25f4d95a…] — BribeFactory
- `0x0d3d15a794db6d185ec2d7fbe7587275a47f146e` **PoolEligibilityOracle** (verified) — PoolEligibilityOracle implementation
- `0xc98fb7b58d4da6c93c4a62bbeaa60932abc96c33` **PoolEligibilityOracleProxy** (verified) [proxy→0x0d3d15a7…] — POOL_ELIGIBILITY_ORACLE (gauge eligibility)
- `0x6fca200fe1f71be1b8714acfb5e9d3a147cced42` **RewardsDistributorV2** (verified) — RewardsDistributor - receives rebase HYDX
- `0x7cba848649bf2557bdf4af9b0d14bc614d8497bf` **TransparentUpgradeableProxy** (verified) [proxy→0xa96af4f0…] — VeArtProxy - ve NFT art
- `0x291a0c1d65101121d130c9e72fdcdd789c47e678` **TransparentUpgradeableProxy** (verified) [proxy→0xdf4c8238…] — gauge CUSTOM_POOL_DEPLOYER
- `0xa96af4f0d265493bdc75e614c389ff5dda3f657b` **VeArtProxy_HYDX** (verified) — VeArtProxy implementation
- `0x9cb9fc7d128f89cbd43bbfd89dbab05d1fa17233` **VoterV5** (verified) — VoterV5 implementation
- `0xc69e3ef39e3ffbce2a1c570f8d3adf76909ef17b` **VoterV5Proxy** (verified) [proxy→0x9cb9fc7d…] — Voter - ve(3,3) hub
- `0x68ed6a9fd3fe6db26def56641c3b251278d8c21d` **VoterV5_ClaimLogic** (verified) — Voter claimLogic (delegatecall target?)
- `0x8cf73eb543c75ba5f2e188d3ce5f8682f2e7f0a3` **VoterV5_GaugeLogic** (verified) — Voter gaugeLogic (delegatecall target?)
- `0x0fc68ce53be957a1aa779f553ad49f6068fff231` **VotingEscrowV2Upgradeable** (verified) — VotingEscrowV2 implementation
- `0x25b2ed7149fb8a05f6ef9407d9c8f878f59cd1e1` **VotingEscrowV2UpgradeableProxy** (verified) [proxy→0x0fc68ce5…] — VotingEscrowV2UpgradeableProxy veHYDX (14.8% holder)

## options
- `0xf524522bbd8fc020033d94f83b83f5b50c9b6ea7` **AlgebraIntegralTwap** (verified) — TwapOracle for OptionToken discount pricing
- `0xb677271ba49d5bb1bab3458f3e50fa7a0a30cc55` **OptionFeeDistributor** (verified) — OptionFeeDistributor implementation
- `0xdb2fc14d19a35d9802ea2c275e5f9f17bc9665cc` **OptionFeeDistributorProxy** (verified) [proxy→0xb677271b…] — feeDistributor for OptionToken payments
- `0xa1136031150e50b015b41f1ca6b2e99e49d8cb78` **OptionTokenV4** (verified) — OptionTokenV4 oHYDX - can sell HYDX at discount (30% holder)
- `0x704e305da17459880837bcd62c8e7644263eb476` **SafeProxy** (verified) [proxy→0x29fcb43b…] — floorReceiver (option floor payments dest)
- `0xeb39e1b0450f318ff1d2795d204ea3808b5d998f` **SimpleFloorGuardian** (verified) — floorGuardian implementation

## liquidity
- `0xdf4c8238e9bdb2a14fa2f3a16cd32f251948eb90` **AlgebraCustomPluginFactory** (verified) — CUSTOM_POOL_DEPLOYER implementation
- `0x36077d39cdc65e1e3fb65810430e5b2c4d5fa29e` **AlgebraFactory** (verified) — AlgebraFactory - pool factory
- `0x51f0b932855986b0e621c9d4db6eee1f4644d3d2` **AlgebraPool** (verified) — AlgebraPool HYDX/USDC 0.05% - main $559K pool
- `0x1595a5d101d69d2a2bab2976839cc8eeeb13ab94` **AlgebraPoolDeployer** (verified) — Algebra poolDeployer
- `0xaf11628e68e8bd45375560e549ab8411fa034d4f` **AlgebraUpgradeablePlugin** (verified) — plugin implementation (main pool hook logic)
- `0xde57c7d4d2e98dafb7cdc59e9c88d28f543ae922` **AlgebraUpgradeablePluginFactory** (verified) — pluginFactory implementation
- `0x7f2a845d49786b089f77d5c77b6a10637594ae22` **AlgebraVaultFactoryStub** (verified) — Algebra vaultFactory
- `0xac396cabf5832a49483b78225d902c0999829993` **BeaconProxy** (verified) [proxy→0x22d23d13…] — AlgebraCommunityVault - pool protocol fees
- `0x3fde14f30732c18476cd9265144ebb1d89f6e8f9` **BeaconProxy** (verified) [proxy→0x6225a2b8…] — communityVault external_bribe
- `0xb69b1c48917cc055c76a93a748b5daa6efa39dee` **BeaconProxy** (verified) [proxy→0x6225a2b8…] — communityVault internal_bribe
- `0x243b6136abf6ef6fc5de3422eb82612d4c4c36cf` **BeaconProxy** (verified) [proxy→0x22d23d13…] — last created gauge (sample instance)
- `0x6225a2b81f83a71c0595449a224fc2385dfaa28d` **BribeV2** (verified) — Bribe implementation (internal+external)
- `0xe33a242990780ab872ae986ad68206478fc85ae1` **Contract** (UNVERIFIED) [proxy→0xaf11628e…] — AlgebraPlugin/hook for main pool
- `0x106937fc03212a762be17d529893a32e47ba13a1` **Contract** (UNVERIFIED) [proxy→0xaf11628e…] — plugin UpgradeableBeacon
- `0x9e904666504580af8562b90d0a54786ae07ae9c7` **Contract** (UNVERIFIED) — MevxExecutor implementation
- `0x2c3baec42114dd0c09dcd9b4402c782c6e34877a` **Contract** (UNVERIFIED) — MevxRouter implementation
- `0x854c9c8d6e7a9ec88592af174a4f040aa080b6c1` **Contract** (UNVERIFIED) — MevX router auxiliary oracle/quoter (stopLoss getter)
- `0xb781a7afcf46dec1fa16a722efd25433d1b9f261` **FarmingCenter** (verified) — Algebra farmingAddress (eternal farming)
- `0x30d5e87ce5c888711477184782126d241a75983e` **GaugeFactoryIncentiveCampaign** (verified) — GaugeFactoryIncentiveCampaign implementation
- `0x22d23d13aa0065ff3233cc7628f59b49dc80480d` **GaugeIncentiveCampaign** (verified) — AlgebraCommunityVault implementation
- `0x1c219ba68a9100e4f3475a624cf225ada02c0f1b` **HydrexBasePluginFactory** (verified) — Algebra defaultPluginFactory
- `0xa28990c78ab53a7ade388200136b3f61debc8cef` **IncentiveCampaignManager** (verified) — campaignManager implementation
- `0x605abd1873737ca9a9ec1cfa52cdfc8ef62c2e1d` **Pair** (verified) — Pair HYDX/USDC classic
- `0xada56cd47fa32d96b835c5c54e54124a3a2403e5` **PairFees** (verified) — PairFees - classic pair fees
- `0x8a797ea0adf48c398fe96fac0d4b6647ed641c54` **ProfitDistributorProxy** (verified) — Mevx ProfitDistributor implementation
- `0x4cb52ea0096606e7843754936944a860e6f12cb6` **SecurityRegistry** (verified) — Mevx SecurityRegistry
- `0x0a607e49d838d4226b129822bd696fafe6ea0f0b` **SecurityRegistry** (verified) — SecurityRegistry #2 (base plugin factory)
- `0xa8dd4c05796801c734e99d5582e90e3a8bd88194` **TransparentUpgradeableProxy** (verified) [proxy→0xde57c7d4…] — plugin pluginFactory
- `0x3a980817e1522c532cc504dba5f5fee9e9096ac5` **TransparentUpgradeableProxy** (verified) [proxy→0x9e904666…] — MevxExecutor
- `0xb32f9894753ee9356ac6734ecf544779c70b1829` **TransparentUpgradeableProxy** (verified) [proxy→0x2c3baec4…] — MevxRouter
- `0x53c67db91f47923d26b0b85a345e484e32a6232f` **TransparentUpgradeableProxy** (verified) [proxy→0x8a797ea0…] — Mevx ProfitDistributor
- `0x416d1a1b4555f715a6d804fcc10805b44409096d` **TransparentUpgradeableProxy** (verified) [proxy→0xa28990c7…] — communityVault campaignManager
- `0x799b61d720afc817c58d944c59c973f01dfa44c8` **UpgradeableBeaconForFactory** (verified) [proxy→0x22d23d13…] — communityVault UpgradeableBeacon

## governance
- `0x74266f2b206d1359b83fc74949ef07176fb3ae03` **EOA** (EOA) — AlgebraFactory owner (authority)
- `0x000000077ac13a2fc7c7a154d28e6251a5e4648b` **EOA-7702** (EOA-7702) — ProfitDistributor owner (MevX authority)
- `0x00ede53f39415e64c78eebd02ad9d383b3a0c0f1` **AlgebraCustomPoolEntryPoint** (verified) — AlgebraFactory POOLS_ADMINISTRATOR #1
- `0xdb5a8524b6127a8fa83083fab0a30dd5df0b42a6` **BeaconFactoryAdmin** (verified) — communityVault beacon owner (can upgrade vault/gauge logic)
- `0xbe50ae4934305c7cdc449862e387ca0515f3402f` **GaugeFactoryIncentiveCampaignProxy** (verified) [proxy→0x30d5e87c…] — communityVault owner (authority)
- `0xfb1bffc9d739b8d520daf37df666da4c687191ea` **GnosisSafeL2** (verified) — GnosisSafe singleton (impl)
- `0xd9e966a6bfa2ae2113a34bb4dd02ded921da50af` **GnosisSafeProxy** (verified) [proxy→0xfb1bffc9…] — GnosisSafeProxy - orig constructor owner (8% holder)
- `0xcf57aa5b3d2f311746f1b1bae8746aacb59db105` **PauseGuardian** (verified) — Voter emergencyCouncil
- `0x3ea45157819c46323cf3a4a3cb93bf58aa7eb81d` **PermissionsRegistry** (verified) — PermissionsRegistry - Voter access control
- `0x41806e1af8c8ba32a2dcb289e52da7bd0a5bf2f7` **PermissionsRegistry** (verified) — feeDistributor PermissionsRegistry
- `0x6e25d241a3ba9e0278a296b398e9678e5ed8ad40` **ProxyAdmin** (verified) — ProxyAdmin - upgrades Minter/Voter/ve/feeDist/artProxy (CRITICAL)
- `0x2689ef6a746f1b253cd772fb045a7563505bed00` **ProxyAdmin** (verified) — plugin-factory ProxyAdmin (owner=factory EOA 0x74266f2b)
- `0x0a70fa8e3f9dfe04348a2747fb2f5a2c6c5c791f` **ProxyAdmin** (verified) — MevX executor ProxyAdmin
- `0x29fcb43b46531bca003ddc8fcb67ffe91900c762` **SafeL2** (verified) — Safe singleton for Minter-owner multisig
- `0x1ae3753d9b60743a89159ccff8e251c60b560311` **SafeProxy** (verified) [proxy→0x29fcb43b…] — Minter owner (authority)
- `0x76954c21e2a6cfc6179c8a03c7426ef2bcf35f4a` **SafeProxy** (verified) [proxy→0x29fcb43b…] — Timelock PROPOSER/CANCELLER Safe (3-of-3)
- `0xdf52b5a03e3f5a4178e4f63e8bc51abe691b898f` **TimelockControllerEnumerable** (verified) — Minter governor (authority)
- `0xa007970f94311b8c5ab46fb2a871bccd95662873` **TransparentUpgradeableProxy** (verified) [proxy→0xeb39e1b0…] — feeDistributor floorGuardian (sets floor price)

## external
- `0x833589fcd6edb6e08f4c7c32d4f71b54bda02913` **FiatTokenProxy** (verified) [proxy→0x2ce6311d…] — USDC (canonical Base, Circle) - pool value leg
- `0x2ce6311ddae708829bc0784c967b7d77d19fd779` **FiatTokenV2_2** (verified) — USDC implementation (Circle FiatTokenV2_2)

## holders
- `0x38f6c6ded6e61cbef5e226ec58cae81cf8029fba` **EOA-7702** (EOA-7702) — whale EOA (7702)
- `0x40fbfe5312330f278824ddbb7521ab77409192f0` **EOA-7702** (EOA-7702) — deployer/creator EOA (7702)