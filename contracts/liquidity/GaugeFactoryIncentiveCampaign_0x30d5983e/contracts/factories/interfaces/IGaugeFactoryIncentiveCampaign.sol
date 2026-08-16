// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IGaugeFactoryV2_Base} from "./IGaugeFactoryV2.sol";

/// @title IGaugeFactoryIncentiveCampaign
/// @notice Factory interface for creating incentive campaign gauges that route rewards to external distributors
interface IGaugeFactoryIncentiveCampaign is IGaugeFactoryV2_Base {
    event IncentiveCampaignManagerSet(address indexed oldManager, address indexed newManager);
    event CampaignManagerSetForGauges(address[] indexed gauges, address indexed campaignManager);

    function initialize(
        address _permissionsRegistry,
        address _gaugeImplementation,
        address _beaconFactoryAdmin,
        address _defaultIncentiveCampaignManager
    ) external;

    function defaultIncentiveCampaignManager() external view returns (address);

    function setIncentiveCampaignManagerDefault(address _manager) external;

    function setCampaignManagerForGauges(address[] memory _gauges, address _campaignManager) external;
}
