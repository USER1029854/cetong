// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

/// @title IVoterV5_GaugeLogic
interface IVoterV5_GaugeLogic is IERC165 {
    function createGauge(
        address _pool,
        uint256 _gaugeType
    ) external returns (address _gauge, address _internal_bribe, address _external_bribe);

    function isValidGaugeType(uint256 _gaugeType) external pure returns (bool);
    
    function MAX_GAUGE_TYPE() external pure returns (uint256);
}
