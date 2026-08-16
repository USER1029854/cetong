// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGaugeV2Base} from "./IGaugeV2.sol";

/// @notice Interface for incentive campaign gauges that route rewards to external distributors
interface IGaugeIncentiveCampaign is IGaugeV2Base, IERC165 {
    event IncentiveDistributed(
        address indexed distributor,
        address indexed token,
        uint256 amount,
        bytes32 indexed campaignId,
        bytes metadata
    );

    function initialize(
        address _campaignManager,
        address _pool,
        address _distribution,
        address _permissionsRegistry
    ) external;

    /// @notice Owner can set or correct the permissions registry for an existing gauge
    function setPermissionsRegistry(address _permissionsRegistry) external;

    function campaignManager() external view returns (address);

    function setCampaignManager(address _campaignManager) external;
}
