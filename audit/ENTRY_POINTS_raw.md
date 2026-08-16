
### HydrexToken (target)
- callable at `0x00000e7efa313f4e11bfff432471ed9423ac6b30`  ·  state-changing external/public: **10**  ·  view/pure: 11  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `approve(address,uint256)`
    - `burn(uint256)`
    - `burnFrom(address,uint256)`
    - `initialMint(address)`
    - `mint(address,uint256)`
    - `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)`
    - `renounceOwnership()`
    - `transfer(address,uint256)`
    - `transferFrom(address,address,uint256)`
    - `transferOwnership(address)`

### MinterUpgradeableV4 [proxy 0xa7d6]
- callable at `0xa7d64625f45548a19b2a19e28e7546bb2839003e`  ·  state-changing external/public: **19**  ·  view/pure: 33  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `_initialize(address[],uint256[],uint256)`
    - `acceptGovernor()`
    - `acceptOwnership()`
    - `acceptTeamAdmin()`
    - `acceptTeamRecipient()`
    - `initialize(address,address,address,address,bool)`
    - `reinitializeV4(address,address)`
    - `renounceOwnership()`
    - `setEmissionSchedule(address)`
    - `setEmissionsGovernor(address)`
    - `setGovernor(address)`
    - `setInitialSupply(uint256)`
    - `setRewardDistributor(address)`
    - `setTeamAdmin(address)`
    - `setTeamRate(uint256)`
    - `setTeamRecipient(address)`
    - `setVoter(address)`
    - `transferOwnership(address)`
    - `update_period()`

### RevisedPhasedEmissionSchedule
- callable at `0x5aaa65af617fa50041325f46ecee5613aaff2727`  ·  state-changing external/public: **2**  ·  view/pure: 19  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `adjustTailEmission(uint256,bool)`
    - `transferGovernance(address)`

### OptionTokenV4 (oHYDX)
- callable at `0xa1136031150e50b015b41f1ca6b2e99e49d8cb78`  ·  state-changing external/public: **22**  ·  view/pure: 38  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `approve(address,uint256)`
    - `burn(uint256)`
    - `decreaseAllowance(address,uint256)`
    - `exercise(uint256,uint256,address,uint256)`
    - `exercise(uint256,uint256,address)`
    - `exerciseExternal(address,uint256,uint256,bytes)`
    - `exerciseVe(uint256,address)`
    - `grantRole(bytes32,address)`
    - `increaseAllowance(address,uint256)`
    - `mint(address,uint256)`
    - `pause()`
    - `renounceRole(bytes32,address)`
    - `revokeRole(bytes32,address)`
    - `setDiscount(uint256)`
    - `setFeeDistributor(address)`
    - `setPaymentConfiguration(address,address,address)`
    - `setTwapSeconds(uint32)`
    - `toggleExternalOption(address,bool)`
    - `togglePermissionedMint()`
    - `transfer(address,uint256)`
    - `transferFrom(address,address,uint256)`
    - `unPause()`

### OptionFeeDistributor [proxy 0xdb2f]
- callable at `0xdb2fc14d19a35d9802ea2c275e5f9f17bc9665cc`  ·  state-changing external/public: **7**  ·  view/pure: 5  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `distribute(address,uint256,uint256)`
    - `initialize(address,address,uint256,address)`
    - `renounceOwnership()`
    - `setFeeReceiver(address,uint256,uint256)`
    - `setFloorGuardian(address)`
    - `setFloorPrice(uint256)`
    - `transferOwnership(address)`

### SimpleFloorGuardian [proxy 0xa007]
- callable at `0xa007970f94311b8c5ab46fb2a871bccd95662873`  ·  state-changing external/public: **5**  ·  view/pure: 4  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `deposit(address,uint256)`
    - `initialize(address,address,address)`
    - `renounceOwnership()`
    - `setFloorReceiver(address)`
    - `transferOwnership(address)`

### AlgebraIntegralTwap
- callable at `0xf524522bbd8fc020033d94f83b83f5b50c9b6ea7`  ·  state-changing external/public: **0**  ·  view/pure: 4  ·  payable: 0  ·  specials: none
- state-changing entry points:

### VotingEscrowV2Upgradeable [proxy 0x25b2]
- callable at `0x25b2ed7149fb8a05f6ef9407d9c8f878f59cd1e1`  ·  state-changing external/public: **29**  ·  view/pure: 55  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `approve(address,uint256)`
    - `burn(uint256)`
    - `checkpoint()`
    - `checkpointDelegatee(address)`
    - `claim(uint256)`
    - `createClaimableLockFor(uint256,uint256,address,address,uint8)`
    - `createDelegatedLockFor(uint256,uint256,address,address,uint8)`
    - `createLock(uint256,uint256,uint8)`
    - `createLockFor(uint256,uint256,address,uint8)`
    - `delegate(uint256,address)`
    - `delegate(address)`
    - `delegateBatch(uint256[],address)`
    - `globalCheckpoint()`
    - `increaseAmount(uint256,uint256)`
    - `increaseUnlockTime(uint256,uint256,bool)`
    - `initialize(string,string,string,address,address,address,address)`
    - `merge(uint256,uint256)`
    - `safeTransferFrom(address,address,uint256)`
    - `safeTransferFrom(address,address,uint256,bytes)`
    - `setApprovalForAll(address,bool)`
    - `setClaimApproval(address,bool,uint256)`
    - `setClaimApprovalForAll(address,bool)`
    - `setClaimRedirectApproval(address,uint256)`
    - `setClaimRedirectApprovalForAll(address,bool)`
    - `setConduitApproval(address,uint256,bool)`
    - `setConduitApprovalConfig(uint8[],string)`
    - `split(uint256[],uint256)`
    - `transferFrom(address,address,uint256)`
    - `unlockRolling(uint256)`

### VoterV5 [proxy 0xc69e]
- callable at `0xc69e3ef39e3ffbce2a1c570f8d3adf76909ef17b`  ·  state-changing external/public: **43**  ·  view/pure: 45  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `_init(address[],address,address,address)`
    - `claimBribes(address[],address[][],uint256)`
    - `claimBribes(address[],address[][])`
    - `claimBribesToRecipientByAddress(address[],address[][],address,address)`
    - `claimBribesToRecipientByTokenId(address[],address[][],uint256,address)`
    - `claimFees(address[],address[][],uint256)`
    - `claimFees(address[],address[][])`
    - `claimFeesToRecipientByAddress(address[],address[][],address,address)`
    - `claimFeesToRecipientByTokenId(address[],address[][],uint256,address)`
    - `claimRewardTokens(address[],address[][])`
    - `claimRewardTokensFor(address[],address[][],address)`
    - `claimRewardTokensToRecipient(address[],address[][],address,address)`
    - `claimRewards(address[])`
    - `claimRewardsFor(address[],address)`
    - `createGauge(address,uint256)`
    - `createGauges(address[],uint256[])`
    - `distribute(address[])`
    - `distribute(uint256,uint256)`
    - `distributeAll()`
    - `distributeFees(address[])`
    - `initialize(address,address,address,address,address,address,string)`
    - `killGauge(address)`
    - `notifyRewardAmount(uint256)`
    - `poke()`
    - `refreshApprovals(uint256,uint256,address)`
    - `reset()`
    - `reviveGauge(address)`
    - `setBribeFactory(address)`
    - `setClaimLogic(address)`
    - `setExternalBribeFor(address,address)`
    - `setFactory(uint256,address,address)`
    - `setGaugeDepositor(address,bool)`
    - `setGaugeLogic(address)`
    - `setInternalBribeFor(address,address)`
    - `setMinter(address)`
    - `setNewBribes(address,address,address)`
    - `setOptionsToken(address)`
    - `setPermissionsRegistry(address)`
    - `setProtocolName(string)`
    - `setVoteDelay(uint256)`
    - `updateWhitelistPool(address[],bool)`
    - `updateWhitelistToken(address[],bool)`
    - `vote(address[],uint256[])`

### VoterV5_GaugeLogic (delegatecall)
- callable at `0x8cf73eb543c75ba5f2e188d3ce5f8682f2e7f0a3`  ·  state-changing external/public: **1**  ·  view/pure: 37  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `createGauge(address,uint256)`

### VoterV5_ClaimLogic (delegatecall)
- callable at `0x68ed6a9fd3fe6db26def56641c3b251278d8c21d`  ·  state-changing external/public: **13**  ·  view/pure: 32  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `claimBribes(address[],address[][],uint256)`
    - `claimBribes(address[],address[][])`
    - `claimBribesToRecipientByAddress(address[],address[][],address,address)`
    - `claimBribesToRecipientByTokenId(address[],address[][],uint256,address)`
    - `claimFees(address[],address[][],uint256)`
    - `claimFees(address[],address[][])`
    - `claimFeesToRecipientByAddress(address[],address[][],address,address)`
    - `claimFeesToRecipientByTokenId(address[],address[][],uint256,address)`
    - `claimRewardTokens(address[],address[][])`
    - `claimRewardTokensFor(address[],address[][],address)`
    - `claimRewardTokensToRecipient(address[],address[][],address,address)`
    - `claimRewards(address[])`
    - `claimRewardsFor(address[],address)`

### RewardsDistributorV2
- callable at `0x6fca200fe1f71be1b8714acfb5e9d3a147cced42`  ·  state-changing external/public: **9**  ·  view/pure: 14  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `checkpoint_token()`
    - `checkpoint_total_supply()`
    - `claim(uint256)`
    - `claimInto(uint256,uint256)`
    - `claimManyInto(uint256[],uint256)`
    - `claim_many(uint256[])`
    - `setDepositor(address)`
    - `setOwner(address)`
    - `withdrawERC20(address)`

### BribeV2 [proxy internal/external]
- callable at `0xb69b1c48917cc055c76a93a748b5daa6efa39dee`  ·  state-changing external/public: **17**  ·  view/pure: 27  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `addRewardToken(address)`
    - `addRewardTokens(address[])`
    - `deposit(uint256,address)`
    - `emergencyRecoverERC20(address,uint256)`
    - `getReward(address[])`
    - `getReward(uint256,address[])`
    - `getRewardForAddress(address,address[])`
    - `getRewardForAddressToRecipient(address,address[],address)`
    - `getRewardForOwner(uint256,address[])`
    - `getRewardToRecipient(uint256,address[],address)`
    - `initialize(address,address,address,string)`
    - `notifyRewardAmount(address,uint256)`
    - `recoverERC20AndUpdateData(address,uint256)`
    - `setMinter(address)`
    - `setOwner(address)`
    - `setVoter(address)`
    - `withdraw(uint256,address)`

### BribeFactoryV4 [proxy 0x58b4]
- callable at `0x58b4f302753003ffc1d70791775b93d0edc87dc1`  ·  state-changing external/public: **18**  ·  view/pure: 14  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `acceptOwnership()`
    - `addRewardToBribe(address,address)`
    - `addRewardToBribes(address,address[])`
    - `addRewardsToBribe(address[],address)`
    - `addRewardsToBribes(address[][],address[])`
    - `createBribe(address,address,address,string)`
    - `initialize(address,address,address,address)`
    - `pushDefaultRewardToken(address)`
    - `recoverERC20AndUpdateData(address[],address[],uint256[])`
    - `recoverERC20From(address[],address[],uint256[])`
    - `removeDefaultRewardToken(address)`
    - `renounceOwnership()`
    - `setBribeMinter(address[],address)`
    - `setBribeOwner(address[],address)`
    - `setBribeVoter(address[],address)`
    - `setPermissionsRegistry(address)`
    - `setVoter(address)`
    - `transferOwnership(address)`

### PermissionsRegistry (voter)
- callable at `0x3ea45157819c46323cf3a4a3cb93bf58aa7eb81d`  ·  state-changing external/public: **8**  ·  view/pure: 19  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `addRole(string)`
    - `removeRole(string)`
    - `removeRoleFrom(address,string)`
    - `renounceRole(string)`
    - `setAdminMultisig(address)`
    - `setEmergencyCouncil(address)`
    - `setRoleFor(address,string)`
    - `setTeamMultisig(address)`

### PermissionsRegistry (feeDist)
- callable at `0x41806e1af8c8ba32a2dcb289e52da7bd0a5bf2f7`  ·  state-changing external/public: **8**  ·  view/pure: 19  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `addRole(string)`
    - `removeRole(string)`
    - `removeRoleFrom(address,string)`
    - `renounceRole(string)`
    - `setAdminMultisig(address)`
    - `setEmergencyCouncil(address)`
    - `setRoleFor(address,string)`
    - `setTeamMultisig(address)`

### GaugeIncentiveCampaign [proxy 0xac39 communityVault]
- callable at `0xac396cabf5832a49483b78225d902c0999829993`  ·  state-changing external/public: **16**  ·  view/pure: 57  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `_withdrawFromCentralPoolSafe(address,uint256)`
    - `acceptOwnership()`
    - `activateEmergencyMode()`
    - `claimFees()`
    - `getReward()`
    - `initialize(address,address,address,address)`
    - `initialize(address,address,address,address,bool)`
    - `notifyRewardAmount(address,uint256)`
    - `renounceOwnership()`
    - `revokeCentralTokenPool()`
    - `setCampaignManager(address)`
    - `setDistribution(address)`
    - `setPermissionsRegistry(address)`
    - `stopEmergencyMode()`
    - `sweepTokens(address[],uint256[],address)`
    - `transferOwnership(address)`

### IncentiveCampaignManager [proxy 0x416d]
- callable at `0x416d1a1b4555f715a6d804fcc10805b44409096d`  ·  state-changing external/public: **14**  ·  view/pure: 21  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `acceptOwnership()`
    - `clearOverride(address,address)`
    - `initialize(address)`
    - `renounceOwnership()`
    - `setDefaultDistributorType(address,uint8)`
    - `setDefaultHydrexConfig(address,tuple)`
    - `setDefaultMerklConfig(address,tuple)`
    - `setDefaultMetroMConfig(address,tuple)`
    - `setDistributorTypeOverride(address,address,uint8)`
    - `setHydrexConfigOverride(address,address,tuple)`
    - `setMaxClaimsPerTx(uint256)`
    - `setMerklConfigOverride(address,address,tuple)`
    - `setMetroMConfigOverride(address,address,tuple)`
    - `transferOwnership(address)`

### GaugeFactoryIncentiveCampaign [proxy 0xbe50]
- callable at `0xbe50ae4934305c7cdc449862e387ca0515f3402f`  ·  state-changing external/public: **14**  ·  view/pure: 14  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `acceptOwnership()`
    - `activateEmergencyMode(address[])`
    - `createGaugeV2(address,address,address,address,address,address,bool)`
    - `initialize(address,address,address,address)`
    - `renounceOwnership()`
    - `setCampaignManagerForGauges(address[],address)`
    - `setCentralTokenPool(address)`
    - `setDistribution(address[],address)`
    - `setGaugeRewarder(address[],address[])`
    - `setIncentiveCampaignManagerDefault(address)`
    - `setPermissionsRegistry(address)`
    - `setPermissionsRegistryForGauges()`
    - `stopEmergencyMode(address[])`
    - `transferOwnership(address)`

### Pair (Solidly HYDX/USDC)
- callable at `0x605abd1873737ca9a9ec1cfa52cdfc8ef62c2e1d`  ·  state-changing external/public: **11**  ·  view/pure: 36  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `approve(address,uint256)`
    - `burn(address)`
    - `claimFees()`
    - `mint(address)`
    - `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)`
    - `setFee(uint256)`
    - `skim(address)`
    - `swap(uint256,uint256,address,bytes)`
    - `sync()`
    - `transfer(address,uint256)`
    - `transferFrom(address,address,uint256)`

### PairFees
- callable at `0xada56cd47fa32d96b835c5c54e54124a3a2403e5`  ·  state-changing external/public: **1**  ·  view/pure: 2  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `claimFeesFor(address,uint256,uint256)`

### PoolEligibilityOracle [proxy 0xc98f]
- callable at `0xc98fb7b58d4da6c93c4a62bbeaa60932abc96c33`  ·  state-changing external/public: **7**  ·  view/pure: 6  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `acceptOwnership()`
    - `initialize(address)`
    - `renounceOwnership()`
    - `setGovernanceOverride(address,bool)`
    - `setOracleUpdater(address)`
    - `setPoolEligibility(address[],bool[])`
    - `transferOwnership(address)`

### VeArtProxy [proxy 0x7cba]
- callable at `0x7cba848649bf2557bdf4af9b0d14bc614d8497bf`  ·  state-changing external/public: **3**  ·  view/pure: 4  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `initialize(string)`
    - `renounceOwnership()`
    - `transferOwnership(address)`

### AlgebraCustomPoolEntryPoint (POOLS_ADMIN)
- callable at `0x00ede53f39415e64c78eebd02ad9d383b3a0c0f1`  ·  state-changing external/public: **7**  ·  view/pure: 1  ·  payable: 0  ·  specials: none
- state-changing entry points:
    - `afterCreatePoolHook(address,address,address)`
    - `beforeCreatePoolHook(address,address,address,address,address,bytes)`
    - `createCustomPool(address,address,address,address,bytes)`
    - `setFee(address,uint16)`
    - `setPlugin(address,address)`
    - `setPluginConfig(address,uint8)`
    - `setTickSpacing(address,int24)`