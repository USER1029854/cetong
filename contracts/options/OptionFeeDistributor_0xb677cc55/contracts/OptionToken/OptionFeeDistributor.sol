// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOptionFeeDistributor} from "./IOptionFeeDistributor.sol";
import {IPermissionsRegistry} from "../interfaces/IPermissionsRegistry.sol";
import {IFloorGuardian} from "./IFloorGuardian.sol";

contract OptionFeeDistributor is IOptionFeeDistributor, Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    FeeReceiver[] public feeReceivers;
    address public permissionsRegistry;
    uint256 public floorPrice;
    address public floorGuardian;
    uint256 constant MAX_FEE_SHARE = 10000;

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[50] private __gap;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @notice Emitted when the fee receiver is updated
    event FeeReceiverUpdated(address indexed oldFeeReceiver, address indexed newFeeReceiver);

    /// @notice Emitted when the floor price is updated
    event FloorPriceUpdated(uint256 oldFloorPrice, uint256 newFloorPrice);

    /// @notice Emitted when the floor guardian is updated
    event FloorGuardianUpdated(address indexed oldFloorGuardian, address indexed newFloorGuardian);

    /// @notice Emitted when fees are distributed
    event FeesDistributed(address indexed token, uint256 amount);

    /// -----------------------------------------------------------------------
    /// Custom Errors
    /// -----------------------------------------------------------------------

    error NotAllowed();
    error InvalidAddress();
    error InsufficientAmount();
    error InvalidFeeShare();
    error InvalidFloorPrice();
    /// -----------------------------------------------------------------------
    /// Initializer
    /// -----------------------------------------------------------------------

    /**
     * @notice Initializes the contract with a fee receiver and permissions registry
     * @dev Sets up the contract with initial settings for fee receiver and permissions registry.
     *      PermissionsRegistry can be address(0) to opt out of permissions.
     * @param _feeReceiver The initial address where fees will be sent
     * @param _permissionsRegistry The address of the PermissionsRegistry contract
     */
    function initialize(
        address _feeReceiver,
        address _permissionsRegistry,
        uint256 _floorPrice,
        address _floorGuardian
    ) public initializer {
        __Ownable_init();
        _setFeeReceiver(_feeReceiver, 10000, 0);
        permissionsRegistry = _permissionsRegistry;
        if (_floorPrice != 0 && _floorGuardian == address(0)) revert InvalidFloorPrice();
        floorPrice = _floorPrice;
        floorGuardian = _floorGuardian;
    }

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier onlyAllowed() {
        if (
            !(owner() == msg.sender ||
                (permissionsRegistry != address(0) &&
                    IPermissionsRegistry(permissionsRegistry).hasRole("FEE_MANAGER", msg.sender)))
        ) {
            revert NotAllowed();
        }
        _;
    }

    /// -----------------------------------------------------------------------
    /// Admin Functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Updates the fee receiver address
     * @dev Can only be called by an allowed address (owner or FEE_MANAGER role)
     * @param _feeReceiver The new fee receiver address
     */
    function setFeeReceiver(address _feeReceiver, uint256 _feeShare, uint256 _index) external onlyAllowed {
        _setFeeReceiver(_feeReceiver, _feeShare, _index);
    }

    /**
     * @notice Updates the floor price for option exercise protection
     * @dev Sets the minimum payment required per unit to prevent oracle manipulation
     * Only callable by owner or accounts with FEE_MANAGER role
     * @param _floorPrice The new floor price in payment token units
     * @custom:security Critical parameter for floor price protection system
     */
    function setFloorPrice(uint256 _floorPrice) external onlyAllowed {
        emit FloorPriceUpdated(floorPrice, _floorPrice);
        floorPrice = _floorPrice;
    }

    /**
     * @notice Updates the floor guardian contract address
     * @dev Floor guardian receives floor price protection funds to ensure minimum protocol revenue
     * Only callable by owner or accounts with FEE_MANAGER role
     * @param _floorGuardian The new floor guardian contract address
     * @custom:security Floor guardian manages critical floor price protection funds
     */
    function setFloorGuardian(address _floorGuardian) external onlyAllowed {
        emit FloorGuardianUpdated(floorGuardian, _floorGuardian);
        floorGuardian = _floorGuardian;
    }

    function _setFeeReceiver(address _feeReceiver, uint256 _feeShare, uint256 _index) private {
        if (_feeReceiver == address(0)) revert InvalidAddress();
        if (_index < feeReceivers.length) {
            emit FeeReceiverUpdated(feeReceivers[_index].receiver, _feeReceiver);
            feeReceivers[_index].receiver = _feeReceiver;
            feeReceivers[_index].feeShare = _feeShare;
        } else {
            feeReceivers.push(FeeReceiver(_feeReceiver, _feeShare));
            emit FeeReceiverUpdated(address(0), _feeReceiver);
        }
        uint256 totalFeeShare = 0;
        for (uint256 i = 0; i < feeReceivers.length; i++) {
            totalFeeShare += feeReceivers[i].feeShare;
        }
        if (totalFeeShare > MAX_FEE_SHARE) revert InvalidFeeShare();
    }

    /// -----------------------------------------------------------------------
    /// Interface Implementations
    /// -----------------------------------------------------------------------

    /**
     * @notice Distributes the specified `amount` of `token` to the fee receiver
     * @dev Requires approval of this contract to spend `amount` of `token`
     * @param token The address of the token being distributed
     * @param payoutAmount The amount of the payout token
     * @param amount The amount of the token to distribute
     */
    function distribute(address token, uint256 payoutAmount, uint256 amount) external override {
        uint256 floorGuardianAmount = (floorPrice * payoutAmount) / (10 ** 18);
        if (floorGuardianAmount > amount) revert InsufficientAmount();
        uint256 surplus = amount - floorGuardianAmount;
        uint256 feeReceiversLength = feeReceivers.length;
        if (surplus > 0 && feeReceiversLength > 0) {
            uint256 toDistribute = surplus;
            for (uint256 i = 0; i < feeReceiversLength; i++) {
                uint256 feeShare = feeReceivers[i].feeShare;
                uint256 feeAmount = (surplus * feeShare) / MAX_FEE_SHARE;
                IERC20(token).safeTransferFrom(msg.sender, feeReceivers[i].receiver, feeAmount);
                toDistribute -= feeAmount;
            }
            if (toDistribute > 0) {
                /// @dev send the dust, product of rounding, to the floor guardian or first fee receiver
                if (floorGuardianAmount > 0) {
                    floorGuardianAmount += toDistribute;
                } else {
                    IERC20(token).safeTransferFrom(msg.sender, feeReceivers[0].receiver, toDistribute);
                }
            }
        }
        if (floorGuardianAmount > 0) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), floorGuardianAmount);
            IERC20(token).approve(floorGuardian, floorGuardianAmount);
            IFloorGuardian(floorGuardian).deposit(token, floorGuardianAmount);
        }
        emit FeesDistributed(token, amount);
    }
}
