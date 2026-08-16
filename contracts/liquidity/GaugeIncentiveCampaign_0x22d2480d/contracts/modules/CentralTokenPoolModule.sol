// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMultiTokenPool} from '../interfaces/IMultiTokenPool.sol';

/**
 * @title CentralTokenPoolModule
 * @notice Abstract module for MultiTokenPool integration
 * @dev Provides reusable logic for integrating with central token pools
 *      Features:
 *      - Zero storage footprint (uses virtual functions)
 *      - Clean separation of concerns
 *      - Reusable across different gauge implementations
 *      - Secure pool revocation mechanism
 */
abstract contract CentralTokenPoolModule {
    using SafeERC20 for IERC20;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    
    /// @notice Emitted when central token pool is revoked
    event CentralTokenPoolRevoked(address indexed gauge, address indexed pool);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    
    /// @notice MultiTokenPool errors
    error PoolAlreadyRevoked();
    error PoolNotEnabled();
    error PoolDepositFailed();
    error PoolWithdrawFailed();
    error InvalidPoolInterface();

    /// -----------------------------------------------------------------------
    /// Virtual Access Functions
    /// -----------------------------------------------------------------------
    
    /// @notice Get the central token pool address - implemented by child contract
    /// @dev Made public for external visibility as requested
    function getCentralTokenPool() public view virtual returns (address);
    
    /// @notice Set the central token pool address with validation
    /// @param newPool The new pool address (can be address(0) to disable)
    function _setCentralTokenPool(address newPool) internal virtual {
        _validatePoolInterface(newPool);
        _setCentralTokenPoolUnchecked(newPool);
    }

    /// @notice Set the central token pool address without validation
    /// @dev ⚠️  INTERNAL IMPLEMENTATION ONLY - DO NOT CALL DIRECTLY!
    ///      This function is automatically called by _setCentralTokenPool() after validation.
    ///      Override this in child contract for actual storage update only.
    ///      Always use _setCentralTokenPool() for safe pool updates.
    /// @param newPool The new pool address (bypasses all safety checks)
    function _setCentralTokenPoolUnchecked(address newPool) internal virtual;

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    /// @notice Modifier to ensure pool is enabled before operations
    modifier onlyWithEnabledPool() {
        if (getCentralTokenPool() == address(0)) revert PoolNotEnabled();
        _;
    }

    /// -----------------------------------------------------------------------
    /// Module Logic
    /// -----------------------------------------------------------------------

    /// @notice Validate that a pool address supports the required interface
    /// @param poolAddress The pool address to validate
    /// @dev Extracted from GaugeV2 initialize function for reusability
    function _validatePoolInterface(address poolAddress) internal view {
        if (poolAddress != address(0)) {
            // Use try-catch to handle cases where the address doesn't support supportsInterface
            // This is especially important for test scenarios
            try IMultiTokenPool(poolAddress).supportsInterface(type(IMultiTokenPool).interfaceId) returns (bool supported) {
                if (!supported) {
                    revert InvalidPoolInterface();
                }
            } catch {
                // If supportsInterface call fails, treat as invalid interface
                // This handles test scenarios and malformed addresses gracefully
                revert InvalidPoolInterface();
            }
        }
    }

    /// @notice Check if central pool routing is enabled
    function _isCentralTokenPoolEnabled() internal view returns (bool) {
        return getCentralTokenPool() != address(0);
    }

    /// @notice Deposit tokens to central pool with proper approval management
    /// @param token The token to deposit
    /// @param amount Amount to deposit
    function _depositToCentralTokenPool(IERC20 token, uint256 amount) internal onlyWithEnabledPool {
        address pool = getCentralTokenPool();

        token.approve(pool, amount);
        IMultiTokenPool(pool).deposit(address(token), amount);
        token.approve(pool, 0);
    }

    /// @notice Withdraw tokens from central pool
    /// @param token The token to withdraw
    /// @param amount Amount to withdraw
    function _withdrawFromCentralTokenPool(IERC20 token, uint256 amount) internal onlyWithEnabledPool {
        address pool = getCentralTokenPool();
        
        IMultiTokenPool(pool).withdraw(address(token), amount);
    }

    /// @notice Revokes the central token pool by withdrawing all tokens
    /// @param token The token to withdraw all of
    function _revokeCentralTokenPool(IERC20 token) internal onlyWithEnabledPool {
        address pool = getCentralTokenPool();
    
        IMultiTokenPool(pool).withdrawAll(address(token));
        emit CentralTokenPoolRevoked(address(this), pool);
        
        // Set pool to address(0) through virtual function
        _setCentralTokenPoolUnchecked(address(0));
    }
} 