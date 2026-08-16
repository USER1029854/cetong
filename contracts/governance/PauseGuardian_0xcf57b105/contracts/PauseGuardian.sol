// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PauseGuardian
 * @notice Fast-path emergency contract set as `emergencyCouncil` in PermissionsRegistry.
 *
 * Any individually authorized address (guardian) can act unilaterally:
 *   - pause(target, selector)        — call a whitelisted zero-arg pause function on any target
 *   - activateEmergencyMode(target)  — call target.activateEmergencyMode()
 *   - killGauge(gauge)               — call VoterV5.killGauge(gauge)
 *
 * Only the owner (Highest Security Safe) can lift an emergency:
 *   - unpause(target, selector)      — call a whitelisted zero-arg unpause function on any target
 *   - stopEmergencyMode(target)      — call target.stopEmergencyMode()
 *
 * Owner also manages the guardian list and the per-target selector whitelist.
 *
 * @dev Invariant: guardians may only invoke selectors present in allowedSelectors[target][selector].
 *      A compromised guardian key cannot call arbitrary functions through this contract.
 * @dev Invariant: only owner can add/remove guardians, manage the whitelist, and lift emergencies.
 */
contract PauseGuardian is Ownable {

    // =========================================================================
    // Storage
    // =========================================================================

    /// @notice VoterV5 address for killGauge fast-path
    address public voter;

    /// @notice Addresses authorized to call guardian functions unilaterally
    mapping(address => bool) public authorized;

    /// @notice Whitelist of (target, selector) pairs guardians may call via pause/unpause
    mapping(address => mapping(bytes4 => bool)) public allowedSelectors;

    // =========================================================================
    // Events
    // =========================================================================

    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event SelectorAllowed(address indexed target, bytes4 selector);
    event SelectorDenied(address indexed target, bytes4 selector);
    event VoterSet(address indexed oldVoter, address indexed newVoter);
    event Paused(address indexed target, bytes4 indexed selector, bytes data);
    event Unpaused(address indexed target, bytes4 indexed selector, bytes data);
    event EmergencyModeActivated(address indexed target);
    event EmergencyModeStopped(address indexed target);
    event GaugeKilled(address indexed gauge);

    // =========================================================================
    // Errors
    // =========================================================================

    error NotGuardian();
    error SelectorNotAllowed(address target, bytes4 selector);
    error CallFailed(address target, bytes4 selector);
    error ZeroAddress();
    error InvalidTarget();

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @param initialOwner       Highest Security Safe — owns this contract
    /// @param _voter             VoterV5 proxy address
    /// @param _initialGuardians  Founders' hot wallets + deployer EOA; keeper added later
    constructor(address initialOwner, address _voter, address[] memory _initialGuardians) Ownable() {
        if (initialOwner == address(0)) revert ZeroAddress();
        if (_voter == address(0)) revert ZeroAddress();
        transferOwnership(initialOwner);
        voter = _voter;
        for (uint256 i = 0; i < _initialGuardians.length; i++) {
            _addGuardian(_initialGuardians[i]);
        }
    }

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyGuardian() {
        if (!authorized[msg.sender]) revert NotGuardian();
        _;
    }

    // =========================================================================
    // Guardian actions (unilateral)
    // =========================================================================

    /// @notice Execute a whitelisted call on a target contract.
    /// @dev Whitelist is on bytes4(data[:4]) — the selector. Callers encode the full calldata
    ///      including any arguments (e.g. abi.encodeWithSelector(sig, arg1, arg2)).
    ///      Zero-arg example:  abi.encodeWithSelector(IPausable.pause.selector)
    ///      Parametric example: abi.encodeWithSelector(IBeacon.lockBeaconUpgradesForDuration.selector, 48 hours)
    function pause(address target, bytes calldata data) external onlyGuardian {
        if (target == address(this)) revert InvalidTarget();
        if (data.length < 4) revert SelectorNotAllowed(target, bytes4(0));
        bytes4 selector = bytes4(data[:4]);
        _requireAllowedSelector(target, selector);
        emit Paused(target, selector, data);
        _call(target, data);
    }

    /// @notice Call target.activateEmergencyMode() — whitelist-gated by hardcoded selector.
    /// @dev Owner must call allowSelector(target, activateEmergencyMode.selector) before
    ///      guardians can use this on a given target. Prevents a compromised guardian key
    ///      from calling activateEmergencyMode() on arbitrary contracts.
    function activateEmergencyMode(address target) external onlyGuardian {
        if (target == address(this)) revert InvalidTarget();
        bytes4 selector = IEmergencyTarget.activateEmergencyMode.selector;
        _requireAllowedSelector(target, selector);
        emit EmergencyModeActivated(target);
        _call(target, abi.encodeWithSelector(selector));
    }

    /// @notice Call VoterV5.killGauge(gauge) — hardcoded target function, no whitelist required.
    /// @dev Works because VoterV5.killGauge now accepts emergencyCouncil callers,
    ///      and this contract is set as emergencyCouncil in PermissionsRegistry.
    function killGauge(address gauge) external onlyGuardian {
        emit GaugeKilled(gauge);
        _call(voter, abi.encodeWithSelector(IKillableGauge.killGauge.selector, gauge));
    }

    // =========================================================================
    // Owner actions — lift emergency
    // =========================================================================

    /// @notice Execute a whitelisted call on a target to lift a pause.
    /// @dev Same encoding rules as pause() — full calldata including any arguments.
    function unpause(address target, bytes calldata data) external onlyOwner {
        if (target == address(this)) revert InvalidTarget();
        if (data.length < 4) revert SelectorNotAllowed(target, bytes4(0));
        bytes4 selector = bytes4(data[:4]);
        _requireAllowedSelector(target, selector);
        emit Unpaused(target, selector, data);
        _call(target, data);
    }

    /// @notice Call target.stopEmergencyMode() — whitelist-gated by hardcoded selector.
    function stopEmergencyMode(address target) external onlyOwner {
        if (target == address(this)) revert InvalidTarget();
        bytes4 selector = IEmergencyTarget.stopEmergencyMode.selector;
        _requireAllowedSelector(target, selector);
        emit EmergencyModeStopped(target);
        _call(target, abi.encodeWithSelector(selector));
    }

    // =========================================================================
    // Owner — guardian management
    // =========================================================================

    function addGuardian(address guardian) external onlyOwner {
        _addGuardian(guardian);
    }

    function removeGuardian(address guardian) external onlyOwner {
        authorized[guardian] = false;
        emit GuardianRemoved(guardian);
    }

    // =========================================================================
    // Owner — selector whitelist management
    // =========================================================================

    function allowSelector(address target, bytes4 selector) external onlyOwner {
        allowedSelectors[target][selector] = true;
        emit SelectorAllowed(target, selector);
    }

    function denySelector(address target, bytes4 selector) external onlyOwner {
        allowedSelectors[target][selector] = false;
        emit SelectorDenied(target, selector);
    }

    // =========================================================================
    // Owner — voter address
    // =========================================================================

    function setVoter(address _voter) external onlyOwner {
        if (_voter == address(0)) revert ZeroAddress();
        emit VoterSet(voter, _voter);
        voter = _voter;
    }

    // =========================================================================
    // Internal
    // =========================================================================

    function _addGuardian(address guardian) internal {
        if (guardian == address(0)) revert ZeroAddress();
        authorized[guardian] = true;
        emit GuardianAdded(guardian);
    }

    function _requireAllowedSelector(address target, bytes4 selector) internal view {
        if (!allowedSelectors[target][selector]) {
            revert SelectorNotAllowed(target, selector);
        }
    }

    function _call(address target, bytes memory data) internal {
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            bytes4 sel;
            if (data.length >= 4) {
                assembly { sel := mload(add(data, 32)) }
            }
            _revert(target, sel, ret);
        }
    }

    function _revert(address target, bytes4 selector, bytes memory ret) internal pure {
        if (ret.length > 0) {
            assembly { revert(add(ret, 32), mload(ret)) }
        }
        revert CallFailed(target, selector);
    }
}

// =========================================================================
// Minimal interfaces — avoids circular imports
// =========================================================================

interface IEmergencyTarget {
    function activateEmergencyMode() external;
    function stopEmergencyMode() external;
}

interface IKillableGauge {
    function killGauge(address gauge) external;
}
