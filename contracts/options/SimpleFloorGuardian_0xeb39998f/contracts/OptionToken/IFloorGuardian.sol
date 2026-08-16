// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

interface IFloorGuardian {
    function deposit(address token, uint256 amount) external;
}
