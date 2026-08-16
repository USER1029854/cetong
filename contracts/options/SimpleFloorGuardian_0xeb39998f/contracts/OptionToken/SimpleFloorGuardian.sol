// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFloorGuardian} from "./IFloorGuardian.sol";
import {IPermissionsRegistry} from "../interfaces/IPermissionsRegistry.sol";

contract SimpleFloorGuardian is IFloorGuardian, Initializable, OwnableUpgradeable {
    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    address public permissionsRegistry;
    IERC20 public principalToken;
    address public floorReceiver;

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[50] private __gap;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @notice Emitted when fees are distributed
    event FeesDistributed(address indexed token, uint256 amount);

    /// -----------------------------------------------------------------------
    /// Custom Errors
    /// -----------------------------------------------------------------------

    error NotAllowed();
    error InvalidToken();
    /// -----------------------------------------------------------------------
    /// Initializer
    /// -----------------------------------------------------------------------

    /**
     * @notice Initializes the contract with a fee receiver and permissions registry
     * @dev Sets up the contract with initial settings for fee receiver and permissions registry.
     *      PermissionsRegistry can be address(0) to opt out of permissions.
     * @param _permissionsRegistry The address of the PermissionsRegistry contract
     * @param _principalToken The address of the principal token
     */
    function initialize(address _permissionsRegistry, address _principalToken, address _floorReceiver) public initializer {
        __Ownable_init();
        permissionsRegistry = _permissionsRegistry;
        principalToken = IERC20(_principalToken);
        floorReceiver = _floorReceiver;
    }

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier onlyAllowed() {
        if (
            !(owner() == msg.sender ||
                (permissionsRegistry != address(0) &&
                    IPermissionsRegistry(permissionsRegistry).hasRole("FLOOR_MANAGER", msg.sender)))
        ) {
            revert NotAllowed();
        }
        _;
    }

    /// -----------------------------------------------------------------------
    /// Admin Functions
    /// -----------------------------------------------------------------------
    /**
     * @notice Updates the address that receives floor guardian funds
     * @dev Only callable by owner or accounts with FLOOR_MANAGER role
     * Changes where floor price protection funds are sent when deposit is called
     * @param _floorReceiver The new address to receive floor guardian funds
     * @custom:security Restricted to authorized accounts only
     */
    function setFloorReceiver(address _floorReceiver) external onlyAllowed {
        floorReceiver = _floorReceiver;
    }

    /// -----------------------------------------------------------------------
    /// Interface Implementations
    /// -----------------------------------------------------------------------

    /**
     * @notice Distributes the specified `amount` of `token` to the fee receiver
     * @dev Requires approval of this contract to spend `amount` of `token`
     * @param token The address of the token being distributed
     * @param amount The amount of the token to distribute
     */
    function deposit(address token, uint256 amount) external {
        if (token != address(principalToken)) revert InvalidToken();
        principalToken.transferFrom(msg.sender, floorReceiver, amount);
        emit FeesDistributed(token, amount);
    }
}
