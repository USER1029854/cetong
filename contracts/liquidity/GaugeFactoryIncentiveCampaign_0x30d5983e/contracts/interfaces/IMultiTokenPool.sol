// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IMultiTokenPool
 * @notice ⚠️  IMPORTANT: STANDARD ERC20 TOKENS ONLY
 * @dev ❌ DO NOT USE WITH:
 *      - Fee-on-transfer tokens
 *      - Deflationary/inflationary tokens
 *      - Rebase tokens (AMPL, etc.)
 *      - Tokens with transfer hooks (ERC777)
 *      - Non-standard tokens that modify balances
 *
 *      ✅ DESIGNED FOR: Standard ERC20 LP tokens from DEX pairs
 *
 *      This pool allows anyone to deposit tokens but only the depositor can withdraw
 *      Address-based isolation ensures secure token storage across multiple users
 *      Designed for cross-chain deployment using CREATE2 for deterministic addresses
 *      Owner can sweep excess tokens for security
 *      Reusable across any protocol needing multi-token storage with user isolation
 */
interface IMultiTokenPool is IERC165 {
    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @notice Emitted when tokens are deposited
    event Deposit(address indexed token, address indexed depositor, uint256 amount);

    /// @notice Emitted when tokens are withdrawn
    event Withdraw(address indexed token, address indexed depositor, uint256 amount);

    /// @notice Emitted when tokens are swept
    event TokenSwept(address indexed token, address indexed owner, uint256 amount);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Error thrown when invalid amount is provided
    error InvalidAmount();

    /// @notice Error thrown when insufficient balance
    error InsufficientBalance();

    /// @notice Error thrown when zero address is provided
    error ZeroAddress();

    /// @notice Error thrown when zero amount is provided
    error ZeroAmount();

    /// @notice Error thrown when non-standard token is detected
    error NonStandardToken();

    /// @notice Error thrown when no excess tokens available for sweep
    error NoExcessTokens();

    /// @notice Error thrown when fallback function is called
    error FallbackNotAllowed();

    /// -----------------------------------------------------------------------
    /// Functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Deposit ERC20 tokens to the pool
     * @param token The ERC20 token address
     * @param amount The amount to deposit
     */
    function deposit(address token, uint256 amount) external;

    /**
     * @notice Deposit ERC20 tokens to the pool on behalf of another address
     * @param token The ERC20 token address
     * @param amount The amount to deposit
     * @param depositor The address that will be credited with the deposit
     */
    function depositFor(address token, uint256 amount, address depositor) external;

    /**
     * @notice Withdraw ERC20 tokens from the pool
     * @param token The ERC20 token address
     * @param amount The amount to withdraw
     */
    function withdraw(address token, uint256 amount) external;

    /**
     * @notice Withdraw all tokens of a specific type for the calling address only
     * @param token The ERC20 token address
     */
    function withdrawAll(address token) external;

    /**
     * @notice Get the balance of a specific token for a user
     * @param token The token address
     * @param user The user address
     * @return The balance
     */
    function balanceOf(address token, address user) external view returns (uint256);

    /**
     * @notice Get total deposited amount of a specific token
     * @param token The token address
     * @return The total amount
     */
    function totalDeposited(address token) external view returns (uint256);

    /**
     * @notice Get the list of all tokens that have been deposited
     * @return Array of token addresses
     */
    function getDepositedTokens() external view returns (address[] memory);

    /**
     * @notice Get user deposit information for a specific token
     * @param user The user address
     * @param token The token address
     * @return amount The deposited amount
     * @return timestamp The deposit timestamp
     */
    function getUserDeposit(address user, address token) external view returns (uint256 amount, uint256 timestamp);

    /// -----------------------------------------------------------------------
    /// Owner Functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Sweep excess tokens from the contract
     * @dev Only owner can call this function and only excess tokens above total deposits can be swept
     * @param token The token address to sweep
     * @param to The address to send swept tokens to
     */
    function sweepExcessTokens(address token, address to) external;
}
