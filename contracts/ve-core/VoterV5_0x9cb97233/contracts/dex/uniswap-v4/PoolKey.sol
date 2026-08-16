// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolIdLibrary} from "./PoolIdLibrary.sol";
// import {Currency} from "./Currency.sol";
// import {IHooks} from "../interfaces/IHooks.sol";

using PoolIdLibrary for PoolKey global;

/// @notice Returns the key for identifying a pool
struct PoolKey {
    /// @notice The lower currency of the pool, sorted numerically
    address currency0; // NOTE: Should be Currency
    /// @notice The higher currency of the pool, sorted numerically
    address currency1; // NOTE: Should be Currency
    /// @notice The pool LP fee, capped at 1_000_000. If the highest bit is 1, the pool has a dynamic fee and must be exactly equal to 0x800000
    uint24 fee;
    /// @notice Ticks that involve positions must be a multiple of tick spacing
    int24 tickSpacing;
    /// @notice The hooks of the pool
    address hooks; // NOTE: Should be IHooks
}
