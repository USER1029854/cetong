// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/// @title PoolEligibilityOracle
/// @notice Registry that tracks which Algebra pools meet criteria for permissionless gauge creation
/// @dev Off-chain service monitors TVL and updates this registry. Governance can also override.
contract PoolEligibilityOracle is Ownable2StepUpgradeable {
    
    /// @notice Maps pool address to eligibility status
    mapping(address => bool) public isPoolEligible;
    
    /// @notice Governance can bypass eligibility checks for specific pools
    mapping(address => bool) public governanceOverride;
    
    /// @notice Backend service address authorized to update eligibility
    address public oracleUpdater;
    
    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;
    
    // ===== EVENTS =====
    
    event PoolEligibilitySet(address indexed pool, bool eligible, uint256 timestamp);
    event GovernanceOverrideSet(address indexed pool, bool overridden);
    event OracleUpdaterSet(address indexed oldUpdater, address indexed newUpdater);
    
    // ===== ERRORS =====
    
    error Unauthorized();
    
    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _oracleUpdater) public initializer {
        __Ownable_init();
        require(_oracleUpdater != address(0), "zero address");
        
        oracleUpdater = _oracleUpdater;
        
        emit OracleUpdaterSet(address(0), _oracleUpdater);
    }
    
    // ===== ORACLE UPDATER FUNCTIONS =====
    
    /// @notice Backend service updates pool eligibility based on TVL checks
    /// @param pools Array of pool addresses to update
    /// @param eligible Array of eligibility statuses
    function setPoolEligibility(
        address[] calldata pools,
        bool[] calldata eligible
    ) external {
        if (msg.sender != oracleUpdater && msg.sender != owner()) revert Unauthorized();
        require(pools.length == eligible.length, "length mismatch");
        
        uint256 timestamp = block.timestamp;
        for (uint256 i = 0; i < pools.length; i++) {
            if (isPoolEligible[pools[i]] == eligible[i]) continue;
            isPoolEligible[pools[i]] = eligible[i];
            emit PoolEligibilitySet(pools[i], eligible[i], timestamp);
        }
    }
    
    // ===== GOVERNANCE FUNCTIONS =====
    
    /// @notice Governance can override eligibility for specific pools
    function setGovernanceOverride(address pool, bool overridden) external onlyOwner {
        require(governanceOverride[pool] != overridden, "no change");
        governanceOverride[pool] = overridden;
        emit GovernanceOverrideSet(pool, overridden);
    }
    
    /// @notice Update the oracle updater address
    function setOracleUpdater(address _newUpdater) external onlyOwner {
        require(_newUpdater != address(0), "zero address");
        require(_newUpdater != oracleUpdater, "no change");
        address oldUpdater = oracleUpdater;
        oracleUpdater = _newUpdater;
        emit OracleUpdaterSet(oldUpdater, _newUpdater);
    }
    
    // ===== VIEW FUNCTIONS =====
    
    /// @notice Check if pool can be used for permissionless gauge creation
    /// @dev Accounts for governance overrides
    function canCreateGauge(address pool) external view returns (bool) {
        // Governance override bypasses all checks
        if (governanceOverride[pool]) return true;
        
        // Check basic eligibility
        return isPoolEligible[pool];
    }
}
