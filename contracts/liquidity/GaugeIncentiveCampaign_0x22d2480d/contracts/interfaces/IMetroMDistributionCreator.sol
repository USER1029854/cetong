// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title IMetroMDistributionCreator
/// @notice Interface for MetroM distribution creator contract based on actual MetroM implementation
interface IMetroMDistributionCreator {
    struct RewardAmount {
        address token;
        uint256 amount;
    }

    struct CreateRewardsCampaignBundle {
        uint32 from;           // Start timestamp
        uint32 to;             // End timestamp
        uint32 kind;           // Campaign type
        bytes data;            // Additional config data
        bytes32 specificationHash; // Campaign specification hash
        RewardAmount[] rewards;    // Array of reward tokens and amounts
    }

    struct CreatePointsCampaignBundle {
        uint32 from;
        uint32 to;
        uint32 kind;
        bytes data;
        bytes32 specificationHash;
        uint256 points;
        address feeToken; // ← REQUIRED
    }

    /// @notice Create campaigns on MetroM (batch creation)
    /// @param rewardsCampaignBundles Array of rewards campaign bundles to create
    /// @param pointsCampaignBundles Array of points campaign bundles to create
    function createCampaigns(
        CreateRewardsCampaignBundle[] calldata rewardsCampaignBundles,
        CreatePointsCampaignBundle[] calldata pointsCampaignBundles
    ) external;

    /// @notice Transfer campaign ownership (optional, for reimbursements)
    /// @param campaignId The ID of the campaign
    /// @param newOwner The address to transfer ownership to
    function transferCampaignOwnership(bytes32 campaignId, address newOwner) external;
}
