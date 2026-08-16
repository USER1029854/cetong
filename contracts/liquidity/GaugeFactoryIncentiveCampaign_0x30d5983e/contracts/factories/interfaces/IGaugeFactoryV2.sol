// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @dev Base interface for the GaugeFactoryV2
interface IGaugeFactoryV2_Base {
    /// @notice Creates a new gauge with the given parameters.
    /// @dev Bribes have been extracted and are now being pulled from the VoterV5. The params have been left for backwards compatibility for V2 gauges.
    function createGaugeV2(
        address _rewardToken,
        address _ve,
        address _token,
        address _distribution,
        /// @dev unused parameter for backwards compatibility
        address /*_internal_bribe*/,
        /// @dev unused parameter for backwards compatibility
        address /*_external_bribe*/,
        bool _isPair
    ) external returns (address);

    function activateEmergencyMode(address[] memory _gauges) external;

    function gauges() external view returns (address[] memory);

    function last_gauge() external view returns (address);

    function length() external view returns (uint256);

    function permissionsRegistry() external view returns (address);

    function setDistribution(address[] memory _gauges, address distro) external;

    function setGaugeRewarder(address[] memory _gauges, address[] memory _rewarder) external;

    function setPermissionsRegistry(address _registry) external;

    function stopEmergencyMode(address[] memory _gauges) external;
    
    /// -----------------------------------------------------------------------
    /// MultiTokenPool Integration
    /// -----------------------------------------------------------------------
    
    /// @notice Gets the current central token pool address (can be address(0) to disable)
    /// @dev CRITICAL: Even if this changes, users must always be able to withdraw their funds
    function centralTokenPool() external view returns (address);
    
    /// @notice Sets the central token pool address
    /// @dev Can be set to address(0) to disable central pooling
    ///      CRITICAL: This change does NOT affect existing funds - users can always withdraw
    function setCentralTokenPool(address _pool) external;
}

/// @dev This interface is used to manage gauges which use UniV2 like LP tokens found in this protocol.
interface IGaugeFactoryV2 is IGaugeFactoryV2_Base {
    function initialize(address _permissionRegistry, address _gaugeBeacon, address _beaconFactoryAdmin) external;
}

/// @dev This interface is used to manage gauges which use GAMMA ALM fungible LP tokens for Concentrated Liquidity on Algebra.
interface IGaugeFactoryV2_Gamma is IGaugeFactoryV2_Base {
    
    function initialize(
        address _permissionsRegistry,
        address _gammaFeeRecipient,
        address _pairFactoryClassic,
        address _feeVaultImplementation,
        address _gaugeImplementation,
        address _beaconFactoryAdmin,
        address _wrappedNativeToken
    ) external;

    function gammaFeeRecipient() external view returns (address);

    function last_feeVault() external view returns (address);

    function setGammaDefaultFeeRecipient(address _rec) external;

    function setGaugeFeeVault(address[] memory _gauges, address _vault) external;
}
