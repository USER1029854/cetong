// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {IGaugeFactoryIncentiveCampaign} from "./interfaces/IGaugeFactoryIncentiveCampaign.sol";
import {IUpgradeableBeacon, IBeaconFactory, IBeaconFactoryAdmin} from "./beacon-factory/IBeaconFactory.sol";
import {IGaugeIncentiveCampaign} from "../interfaces/IGaugeIncentiveCampaign.sol";
import {IPermissionsRegistry} from "../interfaces/IPermissionsRegistry.sol";
import {IMultiTokenPool} from "../interfaces/IMultiTokenPool.sol";

/// @title GaugeFactoryIncentiveCampaign
/// @notice Factory for deploying incentive-campaign gauges that route rewards to external campaign platforms
/// @dev Creates beacon proxies for upgradeable gauges with integrated campaign manager
contract GaugeFactoryIncentiveCampaign is IGaugeFactoryIncentiveCampaign, IBeaconFactory, Ownable2StepUpgradeable {
    string public constant VERSION = "1.0.0";

    address public last_gauge;
    address public permissionsRegistry;
    address public defaultIncentiveCampaignManager;
    address public centralTokenPool;
    address[] internal __gauges;
    IUpgradeableBeacon private __upgradeableBeaconForFactory;

    uint256[50] private __gap;

    event GaugeCreated(address indexed gauge, address indexed pool);
    event PermissionsRegistrySet(address indexed oldRegistry, address indexed newRegistry);
    event CentralTokenPoolSet(address indexed prevPool, address indexed pool);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _permissionsRegistry,
        address _gaugeImplementation,
        address _beaconFactoryAdmin,
        address _defaultIncentiveCampaignManager
    ) public initializer {
        __Ownable_init();
        permissionsRegistry = _permissionsRegistry;

        require(isValidateBeaconImplementation(_gaugeImplementation), "invalid implementation");
        __upgradeableBeaconForFactory = IBeaconFactoryAdmin(_beaconFactoryAdmin).deployUpgradeableBeaconForFactory(
            "GaugeFactoryIncentiveCampaign",
            IBeaconFactory(this),
            _gaugeImplementation
        );
        defaultIncentiveCampaignManager = _defaultIncentiveCampaignManager;
    }

    function getInitData(
        address _campaignManager,
        address _pool,
        address _distribution
    ) public view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IGaugeIncentiveCampaign.initialize.selector,
                _campaignManager,
                _pool,
                _distribution,
                permissionsRegistry
            );
    }

    function createGaugeV2(
        address /*_rewardToken*/,
        address /*_ve*/,
        address _token,
        address _distribution,
        address /*_internal_bribe*/,
        address /*_external_bribe*/,
        bool /*_isPair*/
    ) external returns (address) {
        require(_token != address(0), "zero token");
        require(_distribution != address(0), "zero distribution");
        require(defaultIncentiveCampaignManager != address(0), "campaign manager not set");

        bytes memory implementationData = getInitData(
            defaultIncentiveCampaignManager,
            _token, // pool/campaign identifier
            _distribution
        );

        BeaconProxy newGauge = new BeaconProxy(address(__upgradeableBeaconForFactory), implementationData);

        last_gauge = address(newGauge);
        __gauges.push(last_gauge);

        emit GaugeCreated(last_gauge, _token);

        return last_gauge;
    }

    function isValidateBeaconImplementation(
        address _newImplementation
    ) public view override(IBeaconFactory) returns (bool) {
        return IGaugeIncentiveCampaign(_newImplementation).supportsInterface(type(IGaugeIncentiveCampaign).interfaceId);
    }

    function getUpgradeableBeaconForFactory() external view override(IBeaconFactory) returns (address) {
        return address(__upgradeableBeaconForFactory);
    }

    function getBeaconProxyImplementationForFactory() external view override(IBeaconFactory) returns (address) {
        return __upgradeableBeaconForFactory.implementation();
    }

    modifier onlyAllowed() {
        require(
            owner() == msg.sender || IPermissionsRegistry(permissionsRegistry).hasRole("GAUGE_ADMIN", msg.sender),
            "ERR: GAUGE_ADMIN"
        );
        _;
    }

    function setPermissionsRegistry(address _registry) external onlyAllowed {
        require(_registry != address(0), "zero address");
        require(_registry != permissionsRegistry, "no change");
        emit PermissionsRegistrySet(permissionsRegistry, _registry);
        permissionsRegistry = _registry;
    }

    function setIncentiveCampaignManagerDefault(address _manager) external onlyAllowed {
        require(_manager != address(0), "zero address");
        require(_manager != defaultIncentiveCampaignManager, "no change");
        emit IGaugeFactoryIncentiveCampaign.IncentiveCampaignManagerSet(defaultIncentiveCampaignManager, _manager);
        defaultIncentiveCampaignManager = _manager;
    }

    /// @notice Set default Merkl threshold for gauges created by this factory

    function gauges() external view returns (address[] memory) {
        return __gauges;
    }

    function length() external view returns (uint256) {
        return __gauges.length;
    }

    /// @notice Activate emergency mode for multiple gauges
    function activateEmergencyMode(address[] memory _gauges) external onlyAllowed {
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGaugeIncentiveCampaign(_gauges[i]).activateEmergencyMode();
        }
    }

    /// @notice Stop emergency mode for multiple gauges
    function stopEmergencyMode(address[] memory _gauges) external onlyAllowed {
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGaugeIncentiveCampaign(_gauges[i]).stopEmergencyMode();
        }
    }

    /// @notice Set distribution address for multiple gauges
    function setDistribution(address[] memory _gauges, address distro) external onlyAllowed {
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGaugeIncentiveCampaign(_gauges[i]).setDistribution(distro);
        }
    }

    /// @notice Set gauge rewarder for multiple gauges
    function setGaugeRewarder(address[] memory _gauges, address[] memory _rewarder) external onlyAllowed {
        require(_gauges.length == _rewarder.length, "length mismatch");
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGaugeIncentiveCampaign(_gauges[i]).setGaugeRewarder(_rewarder[i]);
        }
    }

    /// @notice Set campaign manager for multiple gauges (for post-upgrade configuration)
    function setCampaignManagerForGauges(address[] memory _gauges, address _campaignManager) external onlyAllowed {
        require(_campaignManager != address(0), "zero address");
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGaugeIncentiveCampaign(_gauges[i]).setCampaignManager(_campaignManager);
        }
        emit IGaugeFactoryIncentiveCampaign.CampaignManagerSetForGauges(_gauges, _campaignManager);
    }

    /// @notice Set permissions registry for all gauges (for post-upgrade configuration)
    /// @dev This is critical for gauges deployed before permissionsRegistry was added to the implementation
    /// @dev Uses try-catch to skip gauges that already have the registry set to avoid reverting entire transaction
    /// @dev Uses the factory's stored permissionsRegistry to ensure consistency across all gauges
    function setPermissionsRegistryForGauges() external onlyAllowed {
        require(permissionsRegistry != address(0), "zero address");
        for (uint256 i = 0; i < __gauges.length; i++) {
            try IGaugeIncentiveCampaign(__gauges[i]).setPermissionsRegistry(permissionsRegistry) {
                // Successfully set
            } catch {
                // Skip if already set or other error (e.g., already configured)
            }
        }
    }

    function setCentralTokenPool(address _pool) external onlyAllowed {
        require(_pool != centralTokenPool, "no change");
        if (_pool != address(0)) {
            require(
                IMultiTokenPool(_pool).supportsInterface(type(IMultiTokenPool).interfaceId),
                "Invalid pool interface"
            );
        }
        emit CentralTokenPoolSet(centralTokenPool, _pool);
        centralTokenPool = _pool;
    }

    function getCentralTokenPool() external view returns (address) {
        return centralTokenPool;
    }
}
