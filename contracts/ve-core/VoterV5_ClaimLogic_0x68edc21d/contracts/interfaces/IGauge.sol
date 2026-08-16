// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IGauge {
    function notifyRewardAmount(address token, uint amount) external;

    function getReward(address account, address[] memory tokens) external;

    function getReward(address account) external;

    function getRewardToRecipient(address _user, address _recipient, address[] memory tokens) external;

    function claimFees() external returns (uint claimed0, uint claimed1);

    function rewardRate(address _pair) external view returns (uint);

    function balanceOf(address _account) external view returns (uint);

    function isForPair() external view returns (bool);

    function totalSupply() external view returns (uint);

    function earned(address token, address account) external view returns (uint);

    function stakeToken() external view returns (address);

    function setDistribution(address _distro) external;

    function addRewardToken(address _rewardToken) external;

    function removeRewardToken(address _rewardToken) external;

    function updateRewardToken() external;

    function activateEmergencyMode() external;

    function stopEmergencyMode() external;

    function setInternalBribe(address intbribe) external;

    function setGaugeRewarder(address _gr) external;

    function setFeeVault(address _feeVault) external;

    function depositWithLock(address account, uint256 amount, uint256 _lockDuration) external;

    function sweepTokens(address[] memory tokens, uint256[] memory amounts, address to) external;

    function initialize(
        address _rewardToken,
        address _ve,
        address _stakeToken,
        address _distribution,
        address _internal_bribe,
        address _external_bribe,
        bool _isForPair
    ) external;
}
