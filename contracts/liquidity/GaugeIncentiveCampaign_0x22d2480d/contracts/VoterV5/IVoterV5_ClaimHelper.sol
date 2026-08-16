// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVoterV5_ClaimHelper
 * @notice Interface to claim rewards from LP gauges and bribes from VoterV5 
 */
interface IVoterV5_ClaimHelper {
    /// @notice claim LP gauge rewards
    function claimRewards(address[] memory _gauges) external;

    /// @notice claim LP gauge rewards for a given address
    function claimRewardsFor(address[] memory _gauges, address _claimFor) external;

    /// @notice claim specific reward tokens from LP gauges
    function claimRewardTokens(address[] memory _gauges, address[][] memory _tokens) external;

    /// @notice claim specific reward tokens from LP gauges for a given address
    function claimRewardTokensFor(address[] memory _gauges, address[][] memory _tokens, address _claimFor) external;

    /// @notice claim bribes rewards given a TokenID
    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external;

    /// @notice claim fees rewards given a TokenID
    function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId) external;

    /// @notice claim bribes rewards given an address
    function claimBribes(address[] memory _bribes, address[][] memory _tokens) external;

    /// @notice claim fees rewards given an address
    function claimFees(address[] memory _fees, address[][] memory _tokens) external;
}