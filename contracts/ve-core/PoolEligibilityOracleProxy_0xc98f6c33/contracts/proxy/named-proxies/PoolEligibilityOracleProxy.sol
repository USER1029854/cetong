// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract PoolEligibilityOracleProxy is TransparentUpgradeableProxy {
    /// @dev Prevent bytecode collisions
    string public constant NAME = "PoolEligibilityOracleProxy";

    constructor(
        address logic_,
        address admin_,
        bytes memory data_
    ) TransparentUpgradeableProxy(logic_, admin_, data_) {}
}
