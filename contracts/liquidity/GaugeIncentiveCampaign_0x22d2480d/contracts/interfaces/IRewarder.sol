// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    function onReward(uint256 pid, address user, address recipient, uint256 lqdrAmount, uint256 newLpAmount) external;
    function pendingTokens(uint256 pid, address user, uint256 lqdrAmount) external view returns (IERC20[] memory, uint256[] memory);
    function onReward(address user, address recipient, uint256 userBalance) external;
    function onEmergencyWithdrawAmount(address user, uint256 amount) external;
}