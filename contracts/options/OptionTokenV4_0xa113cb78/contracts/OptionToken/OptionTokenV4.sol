// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../libraries/Math.sol";
import {IVotingEscrowV2, IVotingEscrowV2_Data} from "../VoterV5/VotingEscrow/IVotingEscrowV2.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {IPair} from "../interfaces/IPair.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IDynamicTwapOracle} from "./DynamicTwapOracle/IDynamicTwapOracle.sol";
import {IOptionTokenV4} from "./IOptionTokenV4.sol";
import {IOptionFeeDistributor} from "./IOptionFeeDistributor.sol";
import {IOption} from "./IOption.sol";
import {IVersionable} from "../interfaces/IVersionable.sol";

/// @title Option Token V4
/// @notice Option token representing the right to purchase the underlying token
/// at TWAP reduced rate. Similar to call options but with a variable strike
/// price that's always at a certain discount to the market price.
/// @dev
/// - This OptionTokenV4 uses an Algebra style TWAP for pricing
/// - WARN The accuracy of TWAP oracles relies on sufficient liquidity, and they may not provide real-time price data,
///   which can be an issue for applications requiring up-to-date information.
/// Credit to Velocimeter for the original implementation
contract OptionTokenV4 is IOptionTokenV4, IVersionable, ERC20, AccessControlEnumerable {
    using SafeERC20 for IERC20;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------
    string public constant override VERSION = "4.0.0";

    /// @dev MAX_DISCOUNT and MIN_DISCOUNT are handled opposite to discount and veDiscount where 0 = 100% discount
    uint256 public constant MAX_DISCOUNT = 100; // 100%
    uint256 public constant MIN_DISCOUNT = 0; // 0%
    uint256 public constant MAX_TWAP_SECONDS = 2 days;
    uint256 public constant MIN_TWAP_SECONDS = 1 hours;

    /// -----------------------------------------------------------------------
    /// Roles
    /// -----------------------------------------------------------------------
    /// @dev The identifier of the role which maintains other roles and settings
    bytes32 public constant override ADMIN_ROLE = keccak256("ADMIN");

    /// @dev The identifier of the role which is allowed to mint options token
    bytes32 public constant override MINTER_ROLE = keccak256("MINTER");

    /// @dev The identifier of the role which allows accounts to pause exercising options
    /// in case of emergency
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER");

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The token paid by the options token holder during redemption
    IERC20 public override paymentToken;

    /// @notice The underlying token purchased during redemption
    IERC20 public immutable UNDERLYING_TOKEN;

    /// @notice The voter contract
    address public voter;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice The pair contract used to deposit LP option
    IPair public pair;

    /// @notice The oracle contract that provides the current TWAP price to purchase
    /// the underlying token while exercising options (the strike price)
    IDynamicTwapOracle public twapOracle;

    /// @notice The contract that receives the payment tokens when options are exercised
    IOptionFeeDistributor public feeDistributor;

    /// @notice the discount given during exercising. 30 = user pays 30%
    uint256 public discount = 30;

    /// @notice controls the duration of the twap used to calculate the strike price
    uint32 public twapSeconds = 2 hours;

    /// @notice Is exercising options currently paused
    bool public isPaused;

    /// @notice Is minting new options currently permissioned
    bool public permissionedMint = false;

    /// @notice allows to expand options with new contracts
    mapping(address => bool) public isExternalOption;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event Exercise(address indexed sender, address indexed recipient, uint256 amount, uint256 paymentAmount);
    event ExerciseVe(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paymentAmount,
        uint256 nftId
    );
    event SetPaymentConfiguration(
        IPair indexed pair,
        IDynamicTwapOracle indexed twapOracle,
        address indexed paymentToken
    );
    event SetGauge(address indexed newGauge);
    event SetRouter(address indexed router);
    event SetFeeDistributor(IOptionFeeDistributor indexed newFeeDistributor);
    event SetDiscount(uint256 discount);
    event PauseStateChanged(bool isPaused);
    event SetTwapSeconds(uint32 twapSeconds);
    event ToggleExternalOption(address option, bool enabled);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error OptionToken_PastDeadline();
    error OptionToken_NoAdminRole();
    error OptionToken_NoMinterRole();
    error OptionToken_NoPauserRole();
    error OptionToken_SlippageTooHigh();
    error OptionToken_InvalidDiscount();
    error OptionToken_Paused();
    error OptionToken_InvalidTwapSeconds();
    error OptionToken_IncorrectPairToken();
    error OptionToken_IncorrectTwapOracle();
    error OptionToken_InvalidLockDuration();
    error OptionToken_InvalidOption();

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------
    /// @dev A modifier which checks that the caller has the admin role.
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert OptionToken_NoAdminRole();
        _;
    }

    /// @dev A modifier which checks that the caller has the admin or minter role.
    modifier onlyMinter() {
        if (permissionedMint && !hasRole(ADMIN_ROLE, msg.sender) && !hasRole(MINTER_ROLE, msg.sender))
            revert OptionToken_NoMinterRole();
        _;
    }

    /// @dev A modifier which checks that the caller has the pause role.
    modifier onlyPauser() {
        if (!hasRole(PAUSER_ROLE, msg.sender)) revert OptionToken_NoPauserRole();
        _;
    }

    /// @dev A modifier which checks that the deadline has not passed.
    modifier checkDeadline(uint256 _deadline) {
        if (block.timestamp > _deadline) {
            revert OptionToken_PastDeadline();
        }
        _;
    }

    /// @dev A modifier which checks that the contract is not paused.
    modifier notPaused() {
        if (isPaused) {
            revert OptionToken_Paused();
        }
        _;
    }

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /**
     * @notice Initializes the OptionTokenV4 contract with the specified parameters
     * @dev Sets up roles, token approvals, and validates the payment configuration
     * @param _name The name of the option token
     * @param _symbol The symbol of the option token
     * @param _admin The address that will be granted admin roles
     * @param _paymentToken The token used to pay for exercising options
     * @param _underlyingToken The token that can be purchased by exercising options
     * @param _twapOracle The oracle used to calculate TWAP prices for exercise
     * @param _feeDistributor The contract that receives payment tokens and distributes fees
     * @param _voter The voter contract address for accessing voting escrow
     * @param _pair The trading pair for the payment and underlying tokens
     * @custom:security Validates that pair and oracle have correct token configuration
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _admin,
        ERC20 _paymentToken,
        ERC20 _underlyingToken,
        IDynamicTwapOracle _twapOracle,
        IOptionFeeDistributor _feeDistributor,
        address _voter,
        IPair _pair
    ) ERC20(_name, _symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);

        UNDERLYING_TOKEN = _underlyingToken;
        twapOracle = _twapOracle;
        feeDistributor = _feeDistributor;
        voter = _voter;

        _setPaymentConfiguration(_pair, _twapOracle, address(_paymentToken));
        
        emit SetFeeDistributor(_feeDistributor);
        emit SetDiscount(discount);
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Exercises options tokens to purchase the underlying tokens.
    /// @dev The oracle may revert if it cannot give a secure result.
    /// @param _amount The amount of options tokens to exercise
    /// @param _maxPaymentAmount The maximum acceptable amount to pay. Used for slippage protection.
    /// @param _recipient The recipient of the purchased underlying tokens
    /// @return paymentAmount The amount paid to the fee distributor to purchase the underlying tokens
    function exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient
    ) external returns (uint256 paymentAmount) {
        return _exercise(_amount, _maxPaymentAmount, _recipient);
    }

    /// @notice Exercises options tokens to purchase the underlying tokens.
    /// @dev The oracle may revert if it cannot give a secure result.
    /// @param _amount The amount of options tokens to exercise
    /// @param _maxPaymentAmount The maximum acceptable amount to pay. Used for slippage protection.
    /// @param _recipient The recipient of the purchased underlying tokens
    /// @param _deadline The Unix timestamp (in seconds) after which the call will revert
    /// @return The amount paid to the fee distributor to purchase the underlying tokens
    function exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient,
        uint256 _deadline
    ) external checkDeadline(_deadline) returns (uint256) {
        return _exercise(_amount, _maxPaymentAmount, _recipient);
    }

    /**
     * @notice Exercises options tokens to create a permanent voting escrow lock
     * @dev Burns option tokens and creates a permanent veNFT lock for the recipient
     * No payment is required as this creates a permanent lock which benefits the protocol
     * @param _amount The amount of option tokens to exercise and lock permanently
     * @param _recipient The address that will receive the voting escrow NFT
     * @return nftId The token ID of the newly created voting escrow NFT
     * @custom:security Creates permanent locks that cannot be unlocked early
     */
    function exerciseVe(
        uint256 _amount,
        address _recipient
    ) external returns (uint256 nftId) {
        return _exerciseVe(_amount, _recipient);
    }

    /**
     * @notice Exercises options tokens through an external option contract
     * @dev Burns option tokens and delegates the exercise to an approved external contract
     * External option must be whitelisted by admin through toggleExternalOption
     * @param _option The external option contract to use for exercise
     * @param _amount The amount of option tokens to exercise
     * @param _deadline The Unix timestamp after which the transaction will revert
     * @param _data Arbitrary data to pass to the external option contract
     * @return paymentAmount The amount of payment tokens required for the exercise
     * @custom:security Only whitelisted external options can be used
     */
    function exerciseExternal(
        IOption _option,
        uint256 _amount,
        uint256 _deadline,
        bytes calldata _data
    ) external checkDeadline(_deadline) returns (uint256 paymentAmount) {
        if (!isExternalOption[address(_option)]) {
            revert OptionToken_InvalidOption();
        }
        paymentAmount = _option.getPaymentAmount(_amount, _data);
        _burn(msg.sender, _amount);
        _option.paymentToken().safeTransferFrom(msg.sender, address(_option), paymentAmount);
        UNDERLYING_TOKEN.approve(address(_option), 0);
        UNDERLYING_TOKEN.approve(address(_option), _amount);
        _option.exercise(_amount, msg.sender, _data);
        UNDERLYING_TOKEN.approve(address(_option), 0);
    }

    /// -----------------------------------------------------------------------
    /// Public functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Returns the address of the voting escrow contract
     * @dev Retrieves the voting escrow address from the voter contract
     * @return votingEscrow The address of the voting escrow contract
     */
    function getVotingEscrow() external view returns (address votingEscrow) {
        votingEscrow = IVoter(voter).ve();
    }

    /**
     * @notice Returns the minimum payment amount required for option exercise
     * @dev Retrieves the floor price from the fee distributor contract
     * This provides protection against oracle manipulation by ensuring a minimum payment
     * @return The minimum payment amount in payment token units
     */
    function getMinPaymentAmount() public view returns (uint256) {
        return feeDistributor.floorPrice();
    }

    /**
     * @notice Returns the minimum price considering both floor price and discounted TWAP price
     * @dev Calculates both floor price and discounted price, returns the higher value
     * This ensures minimum protocol revenue while providing oracle manipulation protection
     * @param _amount The amount of option tokens to exercise
     * @param _discount The discount percentage to apply (e.g., 30 = 30% of TWAP price)
     * @return The minimum payment amount required, either floor price or discounted price
     */
    function getMinPrice(uint256 _amount, uint256 _discount) public view returns (uint256) {
        uint256 floorPriceAmount = (getMinPaymentAmount() * _amount) / (10 ** IERC20Metadata(address(UNDERLYING_TOKEN)).decimals());
        uint256 discountedAmount = getDiscountedPrice(_amount, _discount);
        /// @dev if the floor price is higher than the discounted amount, use the floor price
        return floorPriceAmount > discountedAmount ? floorPriceAmount : discountedAmount;
    }

    /**
     * @notice Returns the minimum price using the current default discount
     * @dev Convenience function that uses the contract's default discount value
     * @param _amount The amount of option tokens to exercise
     * @return The minimum payment amount required using default discount
     */
    function getMinPrice(uint256 _amount) public view returns (uint256) {
        return getMinPrice(_amount, discount);
    }

    /// @notice Returns the discounted price in paymentTokens for a given amount of options tokens
    /// @param _amount The amount of options tokens to exercise
    /// @return The amount of payment tokens to pay to purchase the underlying tokens
    function getDiscountedPrice(uint256 _amount) public view returns (uint256) {
        return getDiscountedPrice(_amount, discount);
    }

    /// @notice Returns the discounted price in paymentTokens for a given amount of options tokens redeemed to veToken
    /// @param _amount The amount of options tokens to exercise
    /// @param _discount The discount amount
    /// @return The amount of payment tokens to pay to purchase the underlying tokens
    function getDiscountedPrice(uint256 _amount, uint256 _discount) public view returns (uint256) {
        return (getTimeWeightedAveragePrice(_amount) * _discount) / 100;
    }

    /// @notice Returns the average price in payment tokens over period defined in twapSeconds for an amount of tokens
    /// @param _amount The amount of underlying tokens to purchase
    /// @return The amount of payment tokens
    function getTimeWeightedAveragePrice(uint256 _amount) public view returns (uint256) {
        return twapOracle.estimateAmountOut(address(UNDERLYING_TOKEN), uint128(_amount), twapSeconds);
    }

    /// -----------------------------------------------------------------------
    /// Admin functions
    /// -----------------------------------------------------------------------

    /// @notice Sets the twap oracle contract address.
    /// @param _pair The pair contract
    /// @param _twapOracle The twap oracle contract
    /// @param _paymentToken The payment token
    function setPaymentConfiguration(
        IPair _pair,
        IDynamicTwapOracle _twapOracle,
        address _paymentToken
    ) external onlyAdmin {
        _setPaymentConfiguration(_pair, _twapOracle, _paymentToken);
    }

    function _setPaymentConfiguration(IPair _pair, IDynamicTwapOracle _twapOracle, address _paymentToken) internal {
        // Validate Pair
        address token0 = _pair.token0();
        address token1 = _pair.token1();
        if (
            !((token0 == _paymentToken && token1 == address(UNDERLYING_TOKEN)) ||
                (token0 == address(UNDERLYING_TOKEN) && token1 == _paymentToken))
        ) {
            revert OptionToken_IncorrectPairToken();
        }
        pair = _pair;
        // Validate Twap Oracle
        if (
            !((_twapOracle.token0() == _paymentToken && _twapOracle.token1() == address(UNDERLYING_TOKEN)) ||
                (_twapOracle.token0() == address(UNDERLYING_TOKEN) && _twapOracle.token1() == _paymentToken))
        ) {
            revert OptionToken_IncorrectTwapOracle();
        }
        twapOracle = _twapOracle;
        // Set Payment Token
        if (address(paymentToken) != _paymentToken) {
            if (address(paymentToken) != address(0)) {
                paymentToken.approve(address(feeDistributor), 0);
            }
            paymentToken = ERC20(_paymentToken);
            paymentToken.approve(address(feeDistributor), type(uint256).max);
        }

        emit SetPaymentConfiguration(_pair, _twapOracle, _paymentToken);
    }

    /// @notice Sets the fee distributor. Only callable by the admin.
    /// @param _feeDistributor The new fee distributor.
    function setFeeDistributor(IOptionFeeDistributor _feeDistributor) external onlyAdmin {
        paymentToken.approve(address(feeDistributor), 0);
        feeDistributor = _feeDistributor;
        paymentToken.approve(address(_feeDistributor), type(uint256).max);
        emit SetFeeDistributor(_feeDistributor);
    }

    /// @notice Sets the discount amount. Only callable by the admin.
    /// @param _discount The new discount amount.
    function setDiscount(uint256 _discount) external onlyAdmin {
        if (_discount > MAX_DISCOUNT || _discount == MIN_DISCOUNT) {
            revert OptionToken_InvalidDiscount();
        }
        discount = _discount;
        emit SetDiscount(_discount);
    }

    /// @notice Sets the twap seconds to control the length of our twap
    /// @param _twapSeconds The new twap points.
    function setTwapSeconds(uint32 _twapSeconds) external onlyAdmin {
        if (_twapSeconds > MAX_TWAP_SECONDS || _twapSeconds < MIN_TWAP_SECONDS) {
            revert OptionToken_InvalidTwapSeconds();
        }
        twapSeconds = _twapSeconds;
        emit SetTwapSeconds(_twapSeconds);
    }

    /**
     * @notice Burns option tokens and transfers underlying tokens to the admin
     * @dev Emergency function to remove option tokens from circulation and recover underlying tokens
     * Only callable by admin for contract management purposes
     * @param _amount The amount of option tokens to burn and underlying tokens to transfer
     * @custom:security Admin-only function for emergency token management
     */
    function burn(uint256 _amount) external onlyAdmin {
        // transfer underlying tokens to the caller
        UNDERLYING_TOKEN.safeTransfer(msg.sender, _amount);
        // burn option tokens
        _burn(msg.sender, _amount);
    }

    /**
     * @notice Re-enables option exercising after being paused
     * @dev Sets isPaused to false, allowing exercise functions to work normally
     * Only callable by admin to restore normal operations after emergency pause
     * @custom:security Admin-only function to restore contract functionality
     */
    function unPause() external onlyAdmin {
        if (!isPaused) return;
        isPaused = false;
        emit PauseStateChanged(false);
    }

    /**
     * @notice Toggles whether minting requires MINTER_ROLE permission
     * @dev Switches between permissioned and permissionless minting modes
     * When permissionedMint is true, only accounts with MINTER_ROLE can mint
     * When false, any account can mint by providing underlying tokens
     * @custom:security Admin-only function that controls minting access
     */
    function togglePermissionedMint() external onlyAdmin {
        permissionedMint = !permissionedMint;
    }

    /**
     * @notice Enables or disables an external option contract for exerciseExternal
     * @dev Manages the whitelist of external option contracts that can be used with exerciseExternal
     * Only whitelisted external options can be used to prevent malicious contract calls
     * @param option The address of the external option contract to whitelist/blacklist
     * @param enabled True to whitelist the option, false to remove from whitelist
     * @custom:security Admin-only function that controls which external contracts can be used
     */
    function toggleExternalOption(address option, bool enabled) external onlyAdmin {
        isExternalOption[option] = enabled;
        emit ToggleExternalOption(option, enabled);
    }

    /// -----------------------------------------------------------------------
    /// Minter functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Mints new option tokens by depositing underlying tokens
     * @dev Transfers underlying tokens from caller and mints equivalent option tokens
     * Requires MINTER_ROLE if permissionedMint is enabled, otherwise anyone can mint
     * Caller must approve this contract to transfer underlying tokens first
     * @param _to The address that will receive the newly minted option tokens
     * @param _amount The amount of underlying tokens to deposit and option tokens to mint
     * @custom:security Requires appropriate role permissions when permissionedMint is enabled
     */
    function mint(address _to, uint256 _amount) external onlyMinter {
        // transfer underlying tokens from the caller
        UNDERLYING_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        // mint options tokens
        _mint(_to, _amount);
    }

    /// -----------------------------------------------------------------------
    /// Pauser functions
    /// -----------------------------------------------------------------------
    /**
     * @notice Pauses all option exercising functionality
     * @dev Sets isPaused to true, preventing exercise, exerciseVe, and exerciseExternal
     * Emergency function to halt operations in case of security issues or oracle problems
     * Only callable by accounts with PAUSER_ROLE
     * @custom:security Emergency pause mechanism for security incidents
     */
    function pause() external onlyPauser {
        if (isPaused) return;
        isPaused = true;
        emit PauseStateChanged(true);
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient
    ) internal notPaused returns (uint256 paymentAmount) {

        // burn callers tokens
        _burn(msg.sender, _amount);
        paymentAmount = getMinPrice(_amount);
        if (paymentAmount > _maxPaymentAmount) { 
            revert OptionToken_SlippageTooHigh();
        }

        // transfer payment tokens from msg.sender to the fee distributor
        paymentToken.safeTransferFrom(msg.sender, address(this), paymentAmount);
        feeDistributor.distribute(address(paymentToken), _amount, paymentAmount);

        // send underlying tokens to recipient
        UNDERLYING_TOKEN.safeTransfer(_recipient, _amount); // will revert on failure

        emit Exercise(msg.sender, _recipient, _amount, paymentAmount);
    }

    function _exerciseVe(
        uint256 _amount,
        address _recipient
    ) internal notPaused returns (uint256 nftId) {
        // burn callers tokens
        _burn(msg.sender, _amount);

        address votingEscrow = IVoter(voter).ve();

        // lock underlying tokens to vote escrow
        UNDERLYING_TOKEN.approve(votingEscrow, _amount);
        nftId = IVotingEscrowV2(votingEscrow).createLockFor(
            _amount,
            0,
            _recipient,
            IVotingEscrowV2_Data.LockType.PERMANENT
        );
        emit ExerciseVe(msg.sender, _recipient, _amount, 0, nftId);
    }
} 