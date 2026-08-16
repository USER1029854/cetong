// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IGaugeV2
 * @custom:version 2.1.0
 * - 2.1.0 initialize function no longer takes _internal_bribe and _external_bribe params
 */

interface IGaugeV2Base {
    function deposit(uint256 amount) external;

    function depositTo(uint256 amount, address account) external;

    function withdrawAll() external;

    function withdraw(uint256 amount) external;

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

    function stakeToken() external view returns (IERC20);

    function setDistribution(address _distro) external;

    function addRewardToken(address _rewardToken) external;

    function removeRewardToken(address _rewardToken) external;

    function updateRewardToken() external;

    function activateEmergencyMode() external;

    function stopEmergencyMode() external;

    function setGaugeRewarder(address _gr) external;

    function depositWithLock(address account, uint256 amount, uint256 _lockDuration) external;

    function sweepTokens(IERC20[] memory tokens, uint256[] memory amounts, address to) external;

    /// -----------------------------------------------------------------------
    /// MultiTokenPool Integration
    /// -----------------------------------------------------------------------

    /// @notice Gets the central pool address that was set during initialization
    function centralTokenPool() external view returns (address);

    /// @notice Revokes the central token pool by withdrawing all tokens and setting pool to address(0)
    /// @dev Only callable by gauge owner/admin. This is a one-way operation - pool can only be re-enabled via upgrade
    function revokeCentralTokenPool() external;
}

interface IGaugeV2Initialize {
    function initialize(
        address _rewardToken,
        address _ve,
        address _stakeToken,
        address _distribution,
        bool _isForPair
    ) external;
}

interface IGaugeV2 is IGaugeV2Base, IGaugeV2Initialize, IERC165 {}
