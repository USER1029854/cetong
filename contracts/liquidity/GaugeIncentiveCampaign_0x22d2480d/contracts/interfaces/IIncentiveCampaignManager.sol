// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IIncentiveCampaignManager {
    enum DistributorType {
        NONE,
        MERKL,
        METROM,
        HYDREX
    }

    struct MerklConfig {
        address distributionCreator;
        bytes32 campaignId;
        address creator;
        uint32 campaignType;
        uint32 duration;
        bytes campaignData;
    }

    struct MetroMConfig {
        address distributionCreator;
        address poolId;           // Pool address/identifier for the campaign
        address campaignOwner;    // Optional: address to transfer campaign ownership to (for reimbursements)
        bytes32 specificationHash; // Campaign specification hash
    }

    struct HydrexConfig {
        address distributor;      // HydrexIncentiveDistributor address
        uint32 startTimestamp;    // Campaign start time (0 = use current epoch timestamp)
        uint32 duration;          // Campaign duration in seconds
    }

    // ===== EVENTS =====

    event DefaultDistributorTypeSet(
        address indexed token,
        DistributorType oldType,
        DistributorType newType,
        uint256 timestamp
    );
    event DefaultMerklConfigSet(
        address indexed token,
        MerklConfig oldConfig,
        MerklConfig newConfig,
        uint256 timestamp
    );
    event DistributorTypeSet(
        address indexed gauge,
        address indexed token,
        DistributorType oldType,
        DistributorType newType,
        uint256 timestamp
    );
    event MerklConfigSet(
        address indexed gauge,
        address indexed token,
        MerklConfig oldConfig,
        MerklConfig newConfig,
        uint256 timestamp
    );
    event DefaultMetroMConfigSet(
        address indexed token,
        MetroMConfig oldConfig,
        MetroMConfig newConfig,
        uint256 timestamp
    );
    event MetroMConfigSet(
        address indexed gauge,
        address indexed token,
        MetroMConfig oldConfig,
        MetroMConfig newConfig,
        uint256 timestamp
    );
    event DefaultHydrexConfigSet(
        address indexed token,
        HydrexConfig oldConfig,
        HydrexConfig newConfig,
        uint256 timestamp
    );
    event HydrexConfigSet(
        address indexed gauge,
        address indexed token,
        HydrexConfig oldConfig,
        HydrexConfig newConfig,
        uint256 timestamp
    );
    event OverrideCleared(address indexed gauge, address indexed token, uint256 timestamp);

    function setDefaultDistributorType(address token, DistributorType dtype) external;

    function setDefaultMerklConfig(address token, MerklConfig calldata cfg) external;

    function setDefaultMetroMConfig(address token, MetroMConfig calldata cfg) external;

    function setDefaultHydrexConfig(address token, HydrexConfig calldata cfg) external;

    function getDefaultDistributorType(address token) external view returns (DistributorType);

    function getDefaultMerklConfig(address token) external view returns (MerklConfig memory);

    function getDefaultMetroMConfig(address token) external view returns (MetroMConfig memory);

    function getDefaultHydrexConfig(address token) external view returns (HydrexConfig memory);

    function setDistributorTypeOverride(address gauge, address token, DistributorType dtype) external;

    function setMerklConfigOverride(address gauge, address token, MerklConfig calldata cfg) external;

    function setMetroMConfigOverride(address gauge, address token, MetroMConfig calldata cfg) external;

    function setHydrexConfigOverride(address gauge, address token, HydrexConfig calldata cfg) external;

    function clearOverride(address gauge, address token) external;

    function hasOverride(address gauge, address token) external view returns (bool);

    function hasTypeOverride(address gauge, address token) external view returns (bool);

    function hasMerklConfigOverride(address gauge, address token) external view returns (bool);

    function hasMetroMConfigOverride(address gauge, address token) external view returns (bool);

    function hasHydrexConfigOverride(address gauge, address token) external view returns (bool);

    function getDistributorType(address gauge, address token) external view returns (DistributorType);

    function getMerklConfig(address gauge, address token) external view returns (MerklConfig memory);

    function getMetroMConfig(address gauge, address token) external view returns (MetroMConfig memory);

    function getHydrexConfig(address gauge, address token) external view returns (HydrexConfig memory);

    function getEffectiveConfig(
        address gauge,
        address token
    ) external view returns (DistributorType, MerklConfig memory, MetroMConfig memory, HydrexConfig memory);
}
