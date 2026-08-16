// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract GaugeFactoryIncentiveCampaignProxy is TransparentUpgradeableProxy {
    /// @dev Prevent bytecode collisions
    string public constant NAME = "GaugeFactoryIncentiveCampaignProxy";

    constructor(
        address logic_,
        address admin_,
        bytes memory data_
    ) TransparentUpgradeableProxy(logic_, admin_, data_) {}
}

