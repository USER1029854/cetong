// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPermissionsRegistry {
    function adminMultisig() external view returns (address);

    function teamMultisig() external view returns (address);

    function emergencyCouncil() external view returns (address);

    /// @notice Check if an address has a bytes role
    function hasRole(bytes memory role, address caller) external view returns (bool);

    /// @notice Check if an address has a role
    function hasRoleString(string memory role, address _user) external view returns(bool);

    /// @notice Read roles and return array of role strings
    function rolesToString() external view returns(string[] memory __roles);

    /// @notice Read roles return an array of roles in bytes
    function roles() external view returns(bytes[] memory);

    /// @notice Read the number of roles
    function rolesLength() external view returns(uint);

    /// @notice Return addresses for a given role
    function roleToAddresses(string memory role) external view returns(address[] memory _addresses);

    /// @notice Return roles for a given address
    function addressToRole(address _user) external view returns(string[] memory);
}
