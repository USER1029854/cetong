// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GaugeV2, IGaugeV2, IERC165} from "./GaugeV2.sol";
import {IGaugeV2Base} from "./interfaces/IGaugeV2.sol";
import {IGaugeIncentiveCampaign} from "./interfaces/IGaugeIncentiveCampaign.sol";
import {IMerklDistributionCreator} from "./interfaces/IMerklDistributionCreator.sol";
import {IMetroMDistributionCreator} from "./interfaces/IMetroMDistributionCreator.sol";
import {IIncentiveCampaignManager} from "./interfaces/IIncentiveCampaignManager.sol";
import {IPairInfo} from "./interfaces/IPairInfo.sol";
import {IBribe} from "./interfaces/IBribe.sol";
import {IVoterV5} from "./VoterV5/IVoterV5.sol";
import {IPermissionsRegistry} from "./interfaces/IPermissionsRegistry.sol";

interface IHydrexIncentiveDistributor {
    function createCampaign(
        address pool,
        address rewardToken,
        uint256 totalRewards,
        uint32 startTimestamp,
        uint32 endTimestamp
    ) external returns (bytes32 campaignId);
}

/// @title GaugeIncentiveCampaign
/// @notice Non-staking gauge that forwards emissions to external incentive campaign distributors (e.g., Merkl, MetroM, Hydrex) and distributes pool fees to voters
/// @dev
///  - All staking/deposit flows are intentionally disabled; no user balances are tracked
///  - Emissions: pulled from DISTRIBUTION and immediately forwarded to the configured distributor (Merkl, MetroM, etc.)
///  - Fee flow: Algebra pools send fees directly to this gauge (acting as communityVault) → claimFees() sweeps to internal bribe → voters
///  - Distribution config sourced from IncentiveCampaignManager (supports default + per-gauge overrides)
///  - BREAKING CHANGE (v1.1.0+): getEffectiveConfig now includes Hydrex distributor integration with updated signature
///  - HYDREX INTEGRATION: Supports campaign creation via HydrexIncentiveDistributor for Merkle-based reward distribution
contract GaugeIncentiveCampaign is GaugeV2, IGaugeIncentiveCampaign {
    using SafeERC20 for IERC20;

    string public constant VERSION_CAMPAIGN = "1.1.0";

    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// Custom Errors
    /// -----------------------------------------------------------------------

    error NoDistributorConfigured();
    error UnknownDistributorType();
    error ZeroAmount();
    error StakingDisabled();
    error RewardsDisabled();
    error AdminDisabled();
    error ZeroPermissionsRegistry();
    error InvalidStartTimestamp();

    /// -----------------------------------------------------------------------
    /// Storage Variables
    /// -----------------------------------------------------------------------

    address public override campaignManager;
    address public poolAddress; // Algebra pool address

    mapping(address => bool) private _merklConditionsAccepted;
    // New variables for upgradeable storage (append-only)
    address public permissionsRegistry;
    uint256[49] private __gap;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    event PermissionsRegistrySet(address oldRegistry, address newRegistry);
    event SentToTeamMultisig(address indexed token, uint256 amount, address indexed teamMultisig);

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event CampaignManagerSet(address indexed oldManager, address indexed newManager);

    /// @notice Set the Merkl campaign threshold (onlyOwner)
    // Merkl threshold removed; fallback to try/catch behavior when interacting with Merkl distributor.

    // PermissionsRegistry is now set in initialize; no external setter.

    // NOTE: 3-arg initializer removed. Use the 4-arg initializer and pass a valid permissionsRegistry.
    // Deprecated initializer was removed to simplify the ABI and avoid ambiguity when encoding calldata.

    function initialize(
        address _campaignManager,
        address _pool,
        address _distribution,
        address _permissionsRegistry
    ) public override(IGaugeIncentiveCampaign) initializer {
        if (_campaignManager == address(0)) revert ZeroAddress();
        // permissionsRegistry may be zero for legacy use; factory deployments should pass a valid address

        // Get reward token and ve from voter
        address _rewardToken = IVoterV5(_distribution).oToken();
        if (_rewardToken == address(0)) {
            _rewardToken = IVoterV5(_distribution).base();
        }
        address _ve = IVoterV5(_distribution)._ve();

        // Initialize GaugeV2 with isPair=true (pool has token0/token1 for fees)
        __GaugeV2_init(_rewardToken, _ve, _pool, _distribution, true);

        campaignManager = _campaignManager;
        poolAddress = _pool;
        permissionsRegistry = _permissionsRegistry;
        if (_permissionsRegistry != address(0)) emit PermissionsRegistrySet(address(0), _permissionsRegistry);
    }

    /// @notice Owner can set or correct the permissions registry for an existing gauge
    function setPermissionsRegistry(address _permissionsRegistry) external onlyOwner {
        if (_permissionsRegistry == address(0)) revert ZeroAddress();
        if (_permissionsRegistry == permissionsRegistry) revert SameAddress();
        address old = permissionsRegistry;
        permissionsRegistry = _permissionsRegistry;
        emit PermissionsRegistrySet(old, _permissionsRegistry);
    }

    // ===== DISABLED STAKING FUNCTIONS =====

    function deposit(uint256) external pure override(GaugeV2, IGaugeV2Base) {
        revert StakingDisabled();
    }

    function depositTo(uint256, address) external pure override(GaugeV2, IGaugeV2Base) {
        revert StakingDisabled();
    }

    function depositWithLock(address, uint256, uint256) external pure override(GaugeV2, IGaugeV2Base) {
        revert StakingDisabled();
    }

    function withdrawAll() external pure override(GaugeV2, IGaugeV2Base) {
        revert StakingDisabled();
    }

    function withdraw(uint256) external pure override(GaugeV2, IGaugeV2Base) {
        revert StakingDisabled();
    }

    function getReward(address) external pure override(GaugeV2, IGaugeV2Base) {
        revert RewardsDisabled();
    }

    function getReward(address, address[] memory) external pure override(GaugeV2, IGaugeV2Base) {
        revert RewardsDisabled();
    }

    function getRewardToRecipient(address, address, address[] memory) external pure override(GaugeV2, IGaugeV2Base) {
        revert RewardsDisabled();
    }

    // ===== VIEW FUNCTIONS =====

    function balanceOf(address) external pure override(GaugeV2, IGaugeV2Base) returns (uint256) {
        return 0;
    }

    function totalSupply() public pure override(GaugeV2, IGaugeV2Base) returns (uint256) {
        return 0;
    }

    function earned(address) external pure override returns (uint256) {
        return 0;
    }

    function earned(address, address) public pure override(GaugeV2, IGaugeV2Base) returns (uint256) {
        return 0;
    }

    // ===== ADDITIONAL DISABLED STAKING FUNCTIONS =====

    function depositAll() external pure override {
        revert StakingDisabled();
    }

    function emergencyWithdraw() external pure override {
        revert StakingDisabled();
    }

    function emergencyWithdrawAmount(uint256) external pure override {
        revert StakingDisabled();
    }

    function withdrawAllAndHarvest() external pure override {
        revert StakingDisabled();
    }

    // ===== DISABLED ACCOUNTING/VIEW FUNCTIONS =====

    function availableBalance(address) public pure override returns (uint256) {
        return 0;
    }

    function lastTimeRewardApplicable(address) public pure override returns (uint256) {
        return 0;
    }

    function rewardPerToken(address) public pure override returns (uint256) {
        return 0;
    }

    function rewardForDuration(address) public pure override returns (uint256) {
        return 0;
    }

    function periodFinish(address) public pure override returns (uint256) {
        return 0;
    }

    function left(address) external pure override returns (uint256) {
        return 0;
    }

    // ===== DISABLED ADMIN FUNCTIONS =====

    function setGaugeRewarder(address) external pure override(GaugeV2, IGaugeV2Base) {
        revert AdminDisabled();
    }

    function addRewardToken(address) external pure override(GaugeV2, IGaugeV2Base) {
        revert AdminDisabled();
    }

    function removeRewardToken(address) external pure override(GaugeV2, IGaugeV2Base) {
        revert AdminDisabled();
    }

    function updateRewardToken() external pure override(GaugeV2, IGaugeV2Base) {
        revert AdminDisabled();
    }

    // ===== CAMPAIGN-SPECIFIC LOGIC =====

    /// @notice Set campaign manager
    function setCampaignManager(address _campaignManager) external onlyOwner {
        if (_campaignManager == address(0)) revert ZeroAddress();
        if (_campaignManager == campaignManager) revert SameAddress();

        address oldManager = campaignManager;
        campaignManager = _campaignManager;
        emit CampaignManagerSet(oldManager, _campaignManager);
    }

    /// @notice Receive rewards from VoterV5 and forward to external incentive campaigns
    /// @dev Overrides GaugeV2's notifyRewardAmount to forward emissions instead of staking rewards
    function notifyRewardAmount(
        address rewardAddress,
        uint256 rewardAmount
    ) external override(GaugeV2, IGaugeV2Base) nonReentrant isNotEmergency onlyDistribution {
        require(IVoterV5(DISTRIBUTION).isWhitelisted(rewardAddress), "rewards tokens must be whitelisted");
        if (rewardAmount == 0) revert ZeroAmount();

        // Transfer tokens from distribution to this gauge
        uint256 balanceBefore = IERC20(rewardAddress).balanceOf(address(this));
        IERC20(rewardAddress).safeTransferFrom(msg.sender, address(this), rewardAmount);
        uint256 balanceAfter = IERC20(rewardAddress).balanceOf(address(this));
        rewardAmount = balanceAfter - balanceBefore;

        // Get distribution configuration from manager
        (
            IIncentiveCampaignManager.DistributorType dtype,
            IIncentiveCampaignManager.MerklConfig memory merklConfig,
            IIncentiveCampaignManager.MetroMConfig memory metromConfig,
            IIncentiveCampaignManager.HydrexConfig memory hydrexConfig
        ) = IIncentiveCampaignManager(campaignManager).getEffectiveConfig(address(this), rewardAddress);

        // Forward to configured distributor
        if (dtype == IIncentiveCampaignManager.DistributorType.MERKL) {
            _forwardToMerkl(rewardAddress, rewardAmount, merklConfig);
        } else if (dtype == IIncentiveCampaignManager.DistributorType.METROM) {
            _forwardToMetroM(rewardAddress, rewardAmount, metromConfig);
        } else if (dtype == IIncentiveCampaignManager.DistributorType.HYDREX) {
            _forwardToHydrex(rewardAddress, rewardAmount, hydrexConfig);
        } else if (dtype == IIncentiveCampaignManager.DistributorType.NONE) {
            revert NoDistributorConfigured();
        } else {
            revert UnknownDistributorType();
        }
    }

    /// @notice Forward rewards to Merkl distributor
    function _forwardToMerkl(
        address rewardAddress,
        uint256 rewardAmount,
        IIncentiveCampaignManager.MerklConfig memory config
    ) internal {
        require(config.distributionCreator != address(0), "Invalid distributor");
        require(config.creator != address(0), "Invalid creator");
        require(config.duration > 0, "Invalid duration");

        // Approve Merkl distributor
        IERC20(rewardAddress).forceApprove(config.distributionCreator, rewardAmount);

        // Only accept once per distributor
        if (!_merklConditionsAccepted[config.distributionCreator]) {
            IMerklDistributionCreator(config.distributionCreator).acceptConditions();
            _merklConditionsAccepted[config.distributionCreator] = true;
        }

        // Create Merkl campaign — if it fails, fallback to team multisig (treasury)
        IMerklDistributionCreator.CampaignParameters memory params = IMerklDistributionCreator.CampaignParameters({
            campaignId: config.campaignId,
            creator: config.creator,
            rewardToken: rewardAddress,
            amount: rewardAmount,
            campaignType: config.campaignType,
            startTimestamp: uint32(IVoterV5(DISTRIBUTION)._epochTimestamp()),
            duration: config.duration,
            campaignData: config.campaignData
        });

        try IMerklDistributionCreator(config.distributionCreator).createCampaign(params) returns (
            bytes32 merklCampaignId
        ) {
            emit IncentiveDistributed(
                config.distributionCreator,
                rewardAddress,
                rewardAmount,
                merklCampaignId,
                config.campaignData
            );
        } catch {
            // Fallback: send to team multisig (treasury)
            // Revoke approval since campaign creation failed
            IERC20(rewardAddress).forceApprove(config.distributionCreator, 0);

            if (permissionsRegistry == address(0)) revert ZeroPermissionsRegistry();
            address teamMultisig = IPermissionsRegistry(permissionsRegistry).teamMultisig();
            if (teamMultisig == address(0)) revert ZeroAddress();
            IERC20(rewardAddress).safeTransfer(teamMultisig, rewardAmount);
            emit SentToTeamMultisig(rewardAddress, rewardAmount, teamMultisig);
        }
    }

    /// @notice Forward rewards to MetroM distributor
    /// @dev Implementation based on MetroM's AmmPoolLiquidityRewardsCampaignCreator example
    function _forwardToMetroM(
        address rewardAddress,
        uint256 rewardAmount,
        IIncentiveCampaignManager.MetroMConfig memory config
    ) internal {
        require(config.distributionCreator != address(0), "Invalid distributor");
        require(config.poolId != address(0), "Invalid poolId");

        IMetroMDistributionCreator distributor = IMetroMDistributionCreator(config.distributionCreator);

        // Build the reward amount array with single reward token
        IMetroMDistributionCreator.RewardAmount[] memory rewards = new IMetroMDistributionCreator.RewardAmount[](1);
        rewards[0] = IMetroMDistributionCreator.RewardAmount({token: rewardAddress, amount: rewardAmount});

        // Build the campaign bundle
        // Campaign starts now + 5s buffer and runs until the end of the current epoch
        // This ensures startTime is always in the future (MetroM requirement)
        uint32 startTime = uint32(block.timestamp + 5); // slight buffer to ensure startTime > now
        uint32 endTime = uint32(IVoterV5(DISTRIBUTION)._epochTimestamp() + DURATION);

        // Use kind=1 for AMM pool liquidity campaigns, encode poolId in data field
        IMetroMDistributionCreator.CreateRewardsCampaignBundle memory bundle = IMetroMDistributionCreator
            .CreateRewardsCampaignBundle({
                from: startTime,
                to: endTime,
                kind: 1, // AMM pool liquidity campaign type
                data: abi.encode(config.poolId), // Pool address/identifier
                specificationHash: config.specificationHash,
                rewards: rewards
            });

        // Calculate campaign ID (matches MetroM's calculation)
        bytes32 campaignId = keccak256(
            abi.encode(
                address(this), // Campaign creator is this gauge
                bundle.from,
                bundle.to,
                bundle.kind,
                bundle.data,
                bundle.specificationHash,
                bundle.rewards
            )
        );

        // Approve the distributor to spend the reward token
        IERC20(rewardAddress).forceApprove(config.distributionCreator, rewardAmount);

        // Create array with single bundle (batch interface)
        IMetroMDistributionCreator.CreateRewardsCampaignBundle[]
            memory bundleArray = new IMetroMDistributionCreator.CreateRewardsCampaignBundle[](1);
        bundleArray[0] = bundle;

        // Create empty points campaign array
        IMetroMDistributionCreator.CreatePointsCampaignBundle[]
            memory pointsArray = new IMetroMDistributionCreator.CreatePointsCampaignBundle[](0);

        // Call the batch creation function
        try distributor.createCampaigns(bundleArray, pointsArray) {
            // Optionally transfer campaign ownership for reimbursements (KPI campaigns)
            // Note: The new owner must accept ownership in a separate transaction
            if (config.campaignOwner != address(0)) {
                distributor.transferCampaignOwnership(campaignId, config.campaignOwner);
            }

            emit IncentiveDistributed(
                config.distributionCreator,
                rewardAddress,
                rewardAmount,
                campaignId,
                abi.encode(config.poolId)
            );
        } catch {
            // Fallback: send to team multisig (treasury)
            // Revoke approval since campaign creation failed
            IERC20(rewardAddress).forceApprove(config.distributionCreator, 0);

            if (permissionsRegistry == address(0)) revert ZeroPermissionsRegistry();
            address teamMultisig = IPermissionsRegistry(permissionsRegistry).teamMultisig();
            if (teamMultisig == address(0)) revert ZeroAddress();
            IERC20(rewardAddress).safeTransfer(teamMultisig, rewardAmount);
            emit SentToTeamMultisig(rewardAddress, rewardAmount, teamMultisig);
        }
    }

    /// @notice Forward rewards to Hydrex internal distributor
    /// @dev Creates a campaign on HydrexIncentiveDistributor for merkle-based distribution
    function _forwardToHydrex(
        address rewardAddress,
        uint256 rewardAmount,
        IIncentiveCampaignManager.HydrexConfig memory config
    ) internal {
        require(config.distributor != address(0), "Invalid distributor");
        require(config.duration > 0, "Invalid duration");

        // Calculate campaign timestamps
        uint32 startTimestamp = config.startTimestamp;
        if (startTimestamp == 0) {
            // Default: start immediately (use current block timestamp)
            startTimestamp = uint32(block.timestamp);
        } else if (startTimestamp < block.timestamp) {
            // Non-zero start time must not be in the past
            revert InvalidStartTimestamp();
        }
        uint32 endTimestamp = startTimestamp + config.duration;

        // Approve distributor to pull tokens
        IERC20(rewardAddress).forceApprove(config.distributor, rewardAmount);

        // Create campaign on Hydrex distributor
        try IHydrexIncentiveDistributor(config.distributor).createCampaign(
            poolAddress,
            rewardAddress,
            rewardAmount,
            startTimestamp,
            endTimestamp
        ) returns (bytes32 campaignId) {
            emit IncentiveDistributed(
                config.distributor,
                rewardAddress,
                rewardAmount,
                campaignId,
                abi.encode(poolAddress, startTimestamp, endTimestamp)
            );
        } catch {
            // Fallback: send to team multisig (treasury)
            // Revoke approval since campaign creation failed
            IERC20(rewardAddress).forceApprove(config.distributor, 0);

            if (permissionsRegistry == address(0)) revert ZeroPermissionsRegistry();
            address teamMultisig = IPermissionsRegistry(permissionsRegistry).teamMultisig();
            if (teamMultisig == address(0)) revert ZeroAddress();
            IERC20(rewardAddress).safeTransfer(teamMultisig, rewardAmount);
            emit SentToTeamMultisig(rewardAddress, rewardAmount, teamMultisig);
        }
    }

    /// @notice Override _claimFees to sweep token0/token1 from gauge to internal bribe
    /// @dev Fee flow: Algebra pools send fees directly to this gauge (acting as communityVault).
    ///      This function sweeps accumulated fees from the gauge to the internal bribe for voter distribution.
    /// Note: ALL tokens in gauge (including rewardToken) are fees because notifyRewardAmount()
    ///      uses delta accounting and forwards emissions atomically, leaving only fees behind.
    function _claimFees() internal virtual override returns (uint256 claimed0, uint256 claimed1) {
        address _internalBribe = internal_bribe();
        if (_internalBribe == address(0)) return (0, 0);

        // Get token0 and token1 from pool
        address token0 = IPairInfo(poolAddress).token0();
        address token1 = IPairInfo(poolAddress).token1();

        // Get balances in this gauge
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        if (balance0 > 0) {
            IERC20(token0).safeApprove(_internalBribe, 0);
            IERC20(token0).safeApprove(_internalBribe, balance0);
            IBribe(_internalBribe).notifyRewardAmount(token0, balance0);
            claimed0 = balance0;
        }

        if (balance1 > 0) {
            IERC20(token1).safeApprove(_internalBribe, 0);
            IERC20(token1).safeApprove(_internalBribe, balance1);
            IBribe(_internalBribe).notifyRewardAmount(token1, balance1);
            claimed1 = balance1;
        }

        if (claimed0 > 0 || claimed1 > 0) {
            emit ClaimFees(address(this), claimed0, claimed1);
        }

        return (claimed0, claimed1);
    }

    // ===== INTERFACE SUPPORT =====

    function supportsInterface(bytes4 interfaceId) public pure virtual override(GaugeV2, IERC165) returns (bool) {
        return interfaceId == type(IGaugeIncentiveCampaign).interfaceId || super.supportsInterface(interfaceId);
    }
}
