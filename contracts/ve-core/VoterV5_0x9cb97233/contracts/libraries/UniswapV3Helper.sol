// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IUniswapV3Factory} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';

/// @title UniswapV3Helper
/// @notice Helper library for UniswapV3 pool validation and fee tier management
/// @dev Used to abstract UniswapV3-specific logic from gauge creation
library UniswapV3Helper {
    /// @notice Standard UniswapV3 fee tiers (in basis points)
    uint24 public constant FEE_LOW = 500; // 0.05%
    uint24 public constant FEE_MEDIUM = 3000; // 0.30%
    uint24 public constant FEE_HIGH = 10000; // 1.00%

    /// @notice Validates that a pool exists in UniswapV3 factory for given tokens
    /// @param _factory The UniswapV3Factory address
    /// @param _tokenA Token A address
    /// @param _tokenB Token B address
    /// @param _expectedPool The expected pool address to validate
    /// @return isValid True if the pool exists in the factory for any standard fee tier
    function validatePoolExists(
        address _factory,
        address _tokenA,
        address _tokenB,
        address _expectedPool
    ) internal view returns (bool isValid) {
        // Check if the pool matches any of the standard fee tiers
        uint24[3] memory fees = [FEE_LOW, FEE_MEDIUM, FEE_HIGH];

        for (uint256 i = 0; i < fees.length; i++) {
            address factoryPool = IUniswapV3Factory(_factory).getPool(_tokenA, _tokenB, fees[i]);
            if (_expectedPool == factoryPool && factoryPool != address(0)) {
                return true;
            }
        }

        return false;
    }
}
