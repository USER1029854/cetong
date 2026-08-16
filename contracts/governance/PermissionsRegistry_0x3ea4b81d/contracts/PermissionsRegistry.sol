// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IPermissionsRegistry} from "./interfaces/IPermissionsRegistry.sol";
import {IVersionable} from "./interfaces/IVersionable.sol";

/**
 * This contract handles roles and permissions available for the broad part of the protocol.
 */
contract PermissionsRegistry is IPermissionsRegistry, IVersionable {

    /**
     * v1.1.0 -> v2.0.0
     * - Refactor to `adminMultisig` and `teamMultisig`
     * v2.1.0 -> v2.2.0
     * - Add renounceRole support to streamline the deployment process
     * - WARN give deployer VOTER_ADMIN temporarily to set up the protocol, MUST renounce role after deployment
     */
    string public constant override VERSION = "2.2.0";

    /// @notice Control this contract. This must be a strong multisig.
    address private _adminMultisig;

    /// @notice This is the team multisig used for reference.
    address private _teamMultisig;

    /// @notice Control emergency functions in the protocol. Low level access.
    address public emergencyCouncil;

    /// @notice Check if caller has a role active   (role -> caller -> true/false)
    mapping(bytes => mapping(address => bool)) public hasRole;
    mapping(bytes => bool) internal _checkRole;

    mapping(bytes => address[]) internal _roleToAddresses;
    mapping(address => bytes[]) internal _addressToRoles;

    /// @notice Roles array
    bytes[] internal _roles;

    event RoleAdded(bytes role);
    event RoleRemoved(bytes role);
    event RoleSetFor(address indexed user, bytes indexed role);
    event RoleRemovedFor(address indexed user, bytes indexed role);
    event RoleRenounced(address indexed user, bytes indexed role);
    event SetEmergencyCouncil(address indexed council);
    event SetTeamMultisig(address indexed multisig);
    event SetAdminMultisig(address indexed multisig);

    /// -----------------------------------------------------------------------
    /// ROLES
    /// -----------------------------------------------------------------------

    bytes public constant GOVERNANCE = bytes("GOVERNANCE");
    bytes public constant VOTER_ADMIN = bytes("VOTER_ADMIN");
    bytes public constant GAUGE_ADMIN = bytes("GAUGE_ADMIN");
    bytes public constant BRIBE_ADMIN = bytes("BRIBE_ADMIN");
    /// @notice This role is used to manage fees. (ex: OptionsFeeDistributor, or CLFeesVault)
    bytes public constant FEE_MANAGER = bytes("FEE_MANAGER");
    bytes public constant CL_FEES_VAULT_ADMIN = bytes("CL_FEES_VAULT_ADMIN");


    /// -----------------------------------------------------------------------
    /// CONSTRUCTOR
    /// -----------------------------------------------------------------------
    
    constructor(address initialAdmins) {
        _adminMultisig = initialAdmins;
        _teamMultisig = initialAdmins;
        emergencyCouncil = initialAdmins;

        _addRole(GOVERNANCE);
        _addRole(VOTER_ADMIN);
        _addRole(GAUGE_ADMIN);
        _addRole(BRIBE_ADMIN);
        _addRole(FEE_MANAGER);
        _addRole(CL_FEES_VAULT_ADMIN);

        /// @dev deployer gets VOTER_ADMIN temporarily to set up the protocol, MUST renounce role after deployment
        _setRoleFor(msg.sender, string(VOTER_ADMIN));
    }

    modifier onlyAdminMultisig() {
        require(msg.sender == _adminMultisig, "!adminMultisig");
        _;
    }

    /// @dev virtual override getter as state variable is not allowed
    function adminMultisig()
        public
        view
        override(IPermissionsRegistry)
        returns (address)
    {
        return _adminMultisig;
    }

    /// @dev virtual override getter as state variable is not allowed
    function teamMultisig()
        public
        view
        override(IPermissionsRegistry)
        returns (address)
    {
        return _teamMultisig;
    }

    /// -----------------------------------------------------------------------
    /// ROLE DEFINITIONS
    /// -----------------------------------------------------------------------

    /// @notice add a new role
    /// @param  stringRole new role's string (eg role = "GAUGE_ADMIN")
    function addRole(string memory stringRole) external onlyAdminMultisig {
        bytes memory bytesRole = bytes(stringRole);
        _addRole(bytesRole);
    }

    /// @notice Add a role based on bytes
    /// @param bytesRole new role's bytes (eg role = bytes("GAUGE_ADMIN"))
    function _addRole(bytes memory bytesRole) private {
        require(!_checkRole[bytesRole], 'is a role');
        _checkRole[bytesRole] = true;
        _roles.push(bytesRole);
        emit RoleAdded(bytesRole);
    }

    /// @notice Remove a role
    /// @dev    set last one to i_th position then .pop()
    function removeRole(string memory role) external onlyAdminMultisig {
        bytes memory _role = bytes(role);
        require(_checkRole[_role], 'not a role');

        for(uint i = 0; i < _roles.length; i++){
            if(keccak256(_roles[i]) == keccak256(_role)){
                _roles[i] = _roles[_roles.length -1];
                _roles.pop();
                _checkRole[_role] = false;
                emit RoleRemoved(_role);
                break; 
            }
        }

        address[] memory rta = _roleToAddresses[bytes(role)];
        for(uint i = 0; i < rta.length; i++){
            hasRole[bytes(role)][rta[i]] = false;
            emit RoleRemovedFor(rta[i], bytes(role));
            // L-7 fix: Iterate over storage length to avoid OOB access
            bytes[] storage userRoles = _addressToRoles[rta[i]];
            for(uint k = 0; k < userRoles.length; k++){
                if(keccak256(userRoles[k]) == keccak256(bytes(role))){
                    // L-4 fix: Use correct array for swap-and-pop (user's roles, not global _roles)
                    userRoles[k] = userRoles[userRoles.length - 1];
                    userRoles.pop();
                    break; // Exit after first match to prevent index issues
                }
            }
        }
        // L-5 fix: Clear the role-to-addresses mapping to maintain consistency
        delete _roleToAddresses[bytes(role)];
    }

    /// -----------------------------------------------------------------------
    /// ROLE MANAGEMENT
    /// -----------------------------------------------------------------------
    
    /// @notice Set a role for an address
    function setRoleFor(address c, string memory role) external onlyAdminMultisig {
        _setRoleFor(c, role);
    }

    /// @notice Set a role for an address
    function _setRoleFor(address c, string memory role) private {
        bytes memory _role = bytes(role);
        require(_checkRole[_role], 'not a role');
        require(!hasRole[_role][c], 'assigned');

        hasRole[_role][c] = true;

        _roleToAddresses[_role].push(c);
        _addressToRoles[c].push(_role);

        emit RoleSetFor(c, _role);
    }

    /// @notice remove a role from an address
    function removeRoleFrom(address c, string memory role) external onlyAdminMultisig {
        _removeRoleFrom(c, role);
    }

    /// @notice renounce a role for the caller
    function renounceRole(string memory role) external {
        _removeRoleFrom(msg.sender, role);
        emit RoleRenounced(msg.sender, bytes(role));
    }

    /// @notice remove a role from an address
    function _removeRoleFrom(address c, string memory role) private {
        bytes memory _role = bytes(role);
        require(_checkRole[_role], 'not a role');
        require(hasRole[_role][c], 'not assigned');

        hasRole[_role][c] = false;

        address[] storage rta = _roleToAddresses[_role];
        for(uint i = 0; i < rta.length; i++){
            if(rta[i] == c){
                rta[i] = rta[rta.length -1];
                rta.pop();
            }
        }

        bytes[] storage atr = _addressToRoles[c];
        for(uint i = 0; i < atr.length; i++){
            if(keccak256(atr[i]) == keccak256(_role)){
                atr[i] = atr[atr.length -1];
                atr.pop();
            }
        }
        emit RoleRemovedFor(c, bytes(role)); 
    }

    /// -----------------------------------------------------------------------
    /// VIEW
    /// -----------------------------------------------------------------------
    
    /// @notice Check if an address has a role
    function hasRoleString(string memory role, address _user) external view returns(bool){
        return hasRole[bytes(role)][_user];
    }

    /// @notice Read roles and return strings
    function rolesToString() external view returns(string[] memory __roles){
        __roles = new string[](_roles.length);
        for(uint i = 0; i < _roles.length; i++){
            __roles[i] = string(_roles[i]);
        }
    }

    /// @notice Read roles array and return bytes
    function roles() external view returns(bytes[] memory){
        return _roles;
    }

    /// @notice Read roles length
    function rolesLength() external view returns(uint){
        return _roles.length;
    }

     /// @notice Return addresses for a given role
    function roleToAddresses(string memory role) external view returns(address[] memory _addresses){
        return _roleToAddresses[bytes(role)];
    }

    /// @notice Return roles for a given address
    function addressToRole(address _user) external view returns(string[] memory){
        string[] memory _temp = new string[](_addressToRoles[_user].length);
        uint i = 0;
        for(i; i < _temp.length; i++){
            _temp[i] = string(_addressToRoles[_user][i]);
        }
        return _temp;
    }

    
    /// -----------------------------------------------------------------------
    /// HELPERS
    /// -----------------------------------------------------------------------

    /// @notice Helper function to get bytes from a string
    function helper_stringToBytes(string memory _input) public pure returns(bytes memory){
        return bytes(_input);
    }

    /// @notice Helper function to get string from bytes
    function helper_bytesToString(bytes memory _input) public pure returns(string memory){
        return string(_input);
    }


    /// -----------------------------------------------------------------------
    /// EMERGENCY AND MULTISIG
    /// -----------------------------------------------------------------------


    /// @notice set emergency council
    /// @param _new new address    
    function setEmergencyCouncil(address _new) external {
        require(msg.sender == emergencyCouncil || msg.sender == _adminMultisig, "not allowed");
        require(_new != address(0), "addr0");
        require(_new != emergencyCouncil, "same emergencyCouncil");
        emergencyCouncil = _new;

        emit SetEmergencyCouncil(_new);
    }


    /// @notice set team multisig
    /// @param _new new address    
    function setTeamMultisig(address _new) external {
        require(msg.sender == _adminMultisig, "not allowed");
        require(_new != address(0), "addr 0");
        require(_new != _teamMultisig, "same multisig");
        _teamMultisig = _new;
        
        emit SetTeamMultisig(_new);
    }

    /// @notice set admin multisig
    /// @param _new new address    
    function setAdminMultisig(address _new) external {
        require(msg.sender == _adminMultisig, "not allowed");
        require(_new != address(0), "addr0");
        require(_new != _adminMultisig, "same multisig");
        _adminMultisig = _new;
        
        emit SetAdminMultisig(_new);
    }
}