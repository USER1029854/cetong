// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IIncentiveCampaignManager} from "./interfaces/IIncentiveCampaignManager.sol";

interface IHydrexIncentiveDistributorGrace {
    function campaignStartGracePeriod() external view returns (uint256);
}

contract IncentiveCampaignManager is Initializable, Ownable2StepUpgradeable, IIncentiveCampaignManager {
    uint256 internal constant DEFAULT_HYDREX_START_TIME_GRACE_PERIOD = 1 hours;

    /// @notice Maximum claims per batch transaction
    uint256 public maxClaimsPerTx;

    // ===== DEFAULT CONFIGS (per token - applies to all gauges) =====
    mapping(address => DistributorType) public defaultDistributorType;
    mapping(address => MerklConfig) public defaultMerklConfig;
    mapping(address => MetroMConfig) public defaultMetroMConfig;
    mapping(address => HydrexConfig) public defaultHydrexConfig;

    // ===== OVERRIDE CONFIGS (per gauge-token pair) =====
    mapping(address => mapping(address => DistributorType)) private _typeFor;
    mapping(address => mapping(address => MerklConfig)) private _merkl;
    mapping(address => mapping(address => MetroMConfig)) private _metrom;
    mapping(address => mapping(address => HydrexConfig)) private _hydrex;
    mapping(address => mapping(address => bool)) private _hasTypeOverride;
    mapping(address => mapping(address => bool)) private _hasMerklConfigOverride;
    mapping(address => mapping(address => bool)) private _hasMetroMConfigOverride;
    mapping(address => mapping(address => bool)) private _hasHydrexConfigOverride;

    /// @notice DEPRECATED legacy Hydrex start timestamp grace period
    /// @dev Retained for storage/API compatibility only; runtime Hydrex timestamp validation uses distributor grace
    uint256 private _hydrexStartTimeGracePeriod;

    /// @notice Storage gap for future upgrades
    uint256[49] private __gap;

    /// @notice Initialize the contract
    function initialize(address _owner) public initializer {
        __Ownable2Step_init();
        maxClaimsPerTx = 50;
        _hydrexStartTimeGracePeriod = DEFAULT_HYDREX_START_TIME_GRACE_PERIOD;
        
        if (_owner != address(0)) {
            _transferOwnership(_owner);
        }
    }

    /// @notice Set maximum claims per transaction (admin only)
    function setMaxClaimsPerTx(uint256 _maxClaims) external onlyOwner {
        require(_maxClaims > 0, "invalid max claims");
        require(_maxClaims != maxClaimsPerTx, "no change");
        maxClaimsPerTx = _maxClaims;
    }

    // ===== DEFAULT CONFIG SETTERS =====

    /// @notice Set default distributor type for a token (applies to all gauges without override)
    function setDefaultDistributorType(address token, DistributorType distributorType) external onlyOwner {
        require(token != address(0), "zero token");
        require(distributorType != DistributorType.NONE, "invalid type");
        DistributorType oldType = defaultDistributorType[token];
        require(oldType != distributorType, "no change");
        defaultDistributorType[token] = distributorType;
        emit DefaultDistributorTypeSet(token, oldType, distributorType, block.timestamp);
    }

    /// @notice Set default Merkl configuration for a token
    function setDefaultMerklConfig(address token, MerklConfig calldata config) external onlyOwner {
        require(token != address(0), "zero token");
        _validateMerklConfig(config);
        MerklConfig memory oldConfig = defaultMerklConfig[token];
        require(!_isSameMerklConfig(oldConfig, config), "no change");
        defaultMerklConfig[token] = config;
        emit DefaultMerklConfigSet(token, oldConfig, config, block.timestamp);
    }

    /// @notice Set default MetroM configuration for a token
    function setDefaultMetroMConfig(address token, MetroMConfig calldata config) external onlyOwner {
        require(token != address(0), "zero token");
        _validateMetroMConfig(config);
        MetroMConfig memory oldConfig = defaultMetroMConfig[token];
        require(!_isSameMetroMConfig(oldConfig, config), "no change");
        defaultMetroMConfig[token] = config;
        emit DefaultMetroMConfigSet(token, oldConfig, config, block.timestamp);
    }

    /// @notice Set default Hydrex configuration for a token
    function setDefaultHydrexConfig(address token, HydrexConfig calldata config) external onlyOwner {
        require(token != address(0), "zero token");
        _validateHydrexConfig(config);
        HydrexConfig memory oldConfig = defaultHydrexConfig[token];
        require(!_isSameHydrexConfig(oldConfig, config), "no change");
        defaultHydrexConfig[token] = config;
        emit DefaultHydrexConfigSet(token, oldConfig, config, block.timestamp);
    }

    /// @notice Get default distributor type for a token
    function getDefaultDistributorType(address token) external view returns (DistributorType) {
        return defaultDistributorType[token];
    }

    /// @notice Get default Merkl configuration for a token
    function getDefaultMerklConfig(address token) external view returns (MerklConfig memory) {
        return defaultMerklConfig[token];
    }

    /// @notice Get default MetroM configuration for a token
    function getDefaultMetroMConfig(address token) external view returns (MetroMConfig memory) {
        return defaultMetroMConfig[token];
    }

    /// @notice Get default Hydrex configuration for a token
    function getDefaultHydrexConfig(address token) external view returns (HydrexConfig memory) {
        return defaultHydrexConfig[token];
    }

    // ===== OVERRIDE CONFIG SETTERS =====

    /// @notice Set distributor type override for specific gauge-token pair
    function setDistributorTypeOverride(address gauge, address token, DistributorType distributorType) external onlyOwner {
        require(gauge != address(0), "zero gauge");
        require(token != address(0), "zero token");
        DistributorType oldType = _hasTypeOverride[gauge][token] ? _typeFor[gauge][token] : defaultDistributorType[token];
        require(oldType != distributorType, "no change");
        _typeFor[gauge][token] = distributorType;
        _hasTypeOverride[gauge][token] = true;
        emit DistributorTypeSet(gauge, token, oldType, distributorType, block.timestamp);
    }

    /// @notice Set Merkl config override for specific gauge-token pair
    function setMerklConfigOverride(address gauge, address token, MerklConfig calldata config) external onlyOwner {
        require(gauge != address(0), "zero gauge");
        require(token != address(0), "zero token");
        _validateMerklConfig(config);
        MerklConfig memory oldConfig = _hasMerklConfigOverride[gauge][token] ? _merkl[gauge][token] : defaultMerklConfig[token];
        require(!_isSameMerklConfig(oldConfig, config), "no change");
        _merkl[gauge][token] = config;
        _hasMerklConfigOverride[gauge][token] = true;
        emit MerklConfigSet(gauge, token, oldConfig, config, block.timestamp);
    }

    /// @notice Set MetroM config override for specific gauge-token pair
    function setMetroMConfigOverride(address gauge, address token, MetroMConfig calldata config) external onlyOwner {
        require(gauge != address(0), "zero gauge");
        require(token != address(0), "zero token");
        _validateMetroMConfig(config);
        MetroMConfig memory oldConfig = _hasMetroMConfigOverride[gauge][token] ? _metrom[gauge][token] : defaultMetroMConfig[token];
        require(!_isSameMetroMConfig(oldConfig, config), "no change");
        _metrom[gauge][token] = config;
        _hasMetroMConfigOverride[gauge][token] = true;
        emit MetroMConfigSet(gauge, token, oldConfig, config, block.timestamp);
    }

    /// @notice Set Hydrex config override for specific gauge-token pair
    function setHydrexConfigOverride(address gauge, address token, HydrexConfig calldata config) external onlyOwner {
        require(gauge != address(0), "zero gauge");
        require(token != address(0), "zero token");
        _validateHydrexConfig(config);
        HydrexConfig memory oldConfig = _hasHydrexConfigOverride[gauge][token] ? _hydrex[gauge][token] : defaultHydrexConfig[token];
        require(!_isSameHydrexConfig(oldConfig, config), "no change");
        _hydrex[gauge][token] = config;
        _hasHydrexConfigOverride[gauge][token] = true;
        emit HydrexConfigSet(gauge, token, oldConfig, config, block.timestamp);
    }

    /// @notice Clear override config for gauge-token pair, reverting to default
    function clearOverride(address gauge, address token) external onlyOwner {
        require(_hasTypeOverride[gauge][token] || _hasMerklConfigOverride[gauge][token] || _hasMetroMConfigOverride[gauge][token] || _hasHydrexConfigOverride[gauge][token], "no override");
        delete _typeFor[gauge][token];
        delete _merkl[gauge][token];
        delete _metrom[gauge][token];
        delete _hydrex[gauge][token];
        delete _hasTypeOverride[gauge][token];
        delete _hasMerklConfigOverride[gauge][token];
        delete _hasMetroMConfigOverride[gauge][token];
        delete _hasHydrexConfigOverride[gauge][token];
        emit OverrideCleared(gauge, token, block.timestamp);
    }

    /// @notice Check if gauge-token pair has any override config
    function hasOverride(address gauge, address token) external view returns (bool) {
        return _hasTypeOverride[gauge][token] || _hasMerklConfigOverride[gauge][token] || _hasMetroMConfigOverride[gauge][token] || _hasHydrexConfigOverride[gauge][token];
    }

    /// @notice Check if gauge-token pair has type override
    function hasTypeOverride(address gauge, address token) external view returns (bool) {
        return _hasTypeOverride[gauge][token];
    }

    /// @notice Check if gauge-token pair has Merkl config override
    function hasMerklConfigOverride(address gauge, address token) external view returns (bool) {
        return _hasMerklConfigOverride[gauge][token];
    }

    /// @notice Check if gauge-token pair has MetroM config override
    function hasMetroMConfigOverride(address gauge, address token) external view returns (bool) {
        return _hasMetroMConfigOverride[gauge][token];
    }

    /// @notice Check if gauge-token pair has Hydrex config override
    function hasHydrexConfigOverride(address gauge, address token) external view returns (bool) {
        return _hasHydrexConfigOverride[gauge][token];
    }

    // ===== QUERY FUNCTIONS (with default + override logic) =====

    /// @notice Get effective distributor type (override if exists, else default)
    /// @dev View function - returns type even if NONE (caller should validate)
    function getDistributorType(address gauge, address token) external view returns (DistributorType) {
        if (_hasTypeOverride[gauge][token]) {
            return _typeFor[gauge][token];
        }
        return defaultDistributorType[token];
    }

    /// @notice Get effective Merkl config (override if exists, else default)
    /// @dev View function - returns config even if invalid (caller should validate)
    function getMerklConfig(address gauge, address token) external view returns (MerklConfig memory) {
        if (_hasMerklConfigOverride[gauge][token]) {
            return _merkl[gauge][token];
        }
        return defaultMerklConfig[token];
    }

    /// @notice Get effective MetroM config (override if exists, else default)
    /// @dev View function - returns config even if invalid (caller should validate)
    function getMetroMConfig(address gauge, address token) external view returns (MetroMConfig memory) {
        if (_hasMetroMConfigOverride[gauge][token]) {
            return _metrom[gauge][token];
        }
        return defaultMetroMConfig[token];
    }

    /// @notice Get effective Hydrex config (override if exists, else default)
    /// @dev View function - returns config even if invalid (caller should validate)
    function getHydrexConfig(address gauge, address token) external view returns (HydrexConfig memory) {
        if (_hasHydrexConfigOverride[gauge][token]) {
            return _hydrex[gauge][token];
        }
        return defaultHydrexConfig[token];
    }

    /// @notice Get effective distributor type, Merkl config, MetroM config, and Hydrex config in a single read
    /// @dev Each field independently falls back to default if not overridden
    function getEffectiveConfig(
        address gauge,
        address token
    ) external view returns (DistributorType, MerklConfig memory, MetroMConfig memory, HydrexConfig memory) {
        DistributorType distributorType = _hasTypeOverride[gauge][token] 
            ? _typeFor[gauge][token] 
            : defaultDistributorType[token];
        
        MerklConfig memory merklConfig = _hasMerklConfigOverride[gauge][token]
            ? _merkl[gauge][token]
            : defaultMerklConfig[token];
        
        MetroMConfig memory metromConfig = _hasMetroMConfigOverride[gauge][token]
            ? _metrom[gauge][token]
            : defaultMetroMConfig[token];
        
        HydrexConfig memory hydrexConfig = _hasHydrexConfigOverride[gauge][token]
            ? _hydrex[gauge][token]
            : defaultHydrexConfig[token];
        
        return (distributorType, merklConfig, metromConfig, hydrexConfig);
    }

    // ===== VALIDATION =====

    /// @dev Validate Merkl configuration
    function _validateMerklConfig(MerklConfig memory config) private pure {
        require(config.distributionCreator != address(0), "zero distributor");
        require(config.creator != address(0), "zero creator");
        require(config.duration > 0, "zero duration");
    }

    /// @dev Check if two Merkl configs are identical
    function _isSameMerklConfig(MerklConfig memory a, MerklConfig memory b) private pure returns (bool) {
        return a.distributionCreator == b.distributionCreator &&
               a.campaignId == b.campaignId &&
               a.creator == b.creator &&
               a.campaignType == b.campaignType &&
               a.duration == b.duration &&
               keccak256(a.campaignData) == keccak256(b.campaignData);
    }

    /// @dev Validate MetroM configuration
    function _validateMetroMConfig(MetroMConfig memory config) private pure {
        require(config.distributionCreator != address(0), "zero distributor");
        require(config.poolId != address(0), "zero poolId");
        // campaignOwner and specificationHash can be zero (optional)
    }

    /// @dev Check if two MetroM configs are identical
    function _isSameMetroMConfig(MetroMConfig memory a, MetroMConfig memory b) private pure returns (bool) {
        return a.distributionCreator == b.distributionCreator &&
               a.poolId == b.poolId &&
               a.campaignOwner == b.campaignOwner &&
               a.specificationHash == b.specificationHash;
    }

    /// @dev Validate Hydrex configuration
    function _validateHydrexConfig(HydrexConfig memory config) private view {
        require(config.distributor != address(0), "zero distributor");
        // Duration must be at least 1 day (86400 seconds) to match HydrexIncentiveDistributor's minimum
        require(config.duration >= 1 days, "duration too short");
        // Fail fast for stale timestamps based on the target distributor's live grace period.
        // The distributor remains the final source of truth at campaign creation time.
        if (config.startTimestamp != 0 && config.startTimestamp < block.timestamp) {
            uint256 gracePeriod = IHydrexIncentiveDistributorGrace(config.distributor).campaignStartGracePeriod();
            require(
                uint256(config.startTimestamp) + gracePeriod >= block.timestamp,
                "startTimestamp in past"
            );
        }
    }

    /// @dev Check if two Hydrex configs are identical
    function _isSameHydrexConfig(HydrexConfig memory a, HydrexConfig memory b) private pure returns (bool) {
        return a.distributor == b.distributor &&
               a.startTimestamp == b.startTimestamp &&
               a.duration == b.duration;
    }
}
