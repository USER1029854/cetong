// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IBribe is IERC165 {
    function deposit(uint amount, address account) external;

    function withdraw(uint amount, address account) external;

    function getRewardForOwner(uint tokenId, address[] memory tokens) external;

    function getRewardForAddress(address _owner, address[] memory tokens) external;

    function notifyRewardAmount(address token, uint amount) external;

    function addRewardToken(address _rewardsToken) external;

    function addRewardTokens(address[] memory _rewardsToken) external;

    function setVoter(address _Voter) external;

    function setMinter(address _Voter) external;

    function setOwner(address _Voter) external;

    function emergencyRecoverERC20(address tokenAddress, uint256 tokenAmount) external;

    function recoverERC20AndUpdateData(address tokenAddress, uint256 tokenAmount) external;

    /// @notice Claim rewards for a token ID and send to recipient
    function getRewardToRecipient(uint256 tokenId, address[] memory tokens, address _recipient) external;

    /// @notice Claim rewards for an address and send to recipient
    function getRewardForAddressToRecipient(address _owner, address[] memory tokens, address _recipient) external;
}

interface IBribe_Init is IBribe {
    function initialize(address _owner, address _voter, address _bribeFactory, string memory _type) external;
}
