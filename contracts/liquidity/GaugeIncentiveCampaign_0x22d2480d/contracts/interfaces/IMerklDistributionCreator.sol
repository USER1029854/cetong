// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMerklDistributionCreator {
    struct CampaignParameters {
        bytes32 campaignId;
        address creator;
        address rewardToken;
        uint256 amount;
        uint32 campaignType;
        uint32 startTimestamp;
        uint32 duration;
        bytes campaignData;
    }

    /// @notice Create a new Merkl campaign with the given parameters
    /// @param params Campaign parameters including reward token, amount, duration, etc.
    /// @return campaignId The actual campaign ID created/used by Merkl distributor
    function createCampaign(CampaignParameters memory params) external returns (bytes32 campaignId);
    function acceptConditions() external;
    function userSignatureWhitelist(address user) external view returns (uint256);
}
