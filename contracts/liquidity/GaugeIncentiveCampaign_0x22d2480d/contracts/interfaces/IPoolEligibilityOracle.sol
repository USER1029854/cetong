// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPoolEligibilityOracle {
    function canCreateGauge(address pool) external view returns (bool);
    function isPoolEligible(address pool) external view returns (bool);
    function governanceOverride(address pool) external view returns (bool);
    function oracleUpdater() external view returns (address);
}
