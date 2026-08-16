// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title IAlgebraFactoryCustom
/// @notice Minimal interface for the AlgebraFactory custom-pool registry.
/// @dev The AlgebraFactory interface shipped in `@cryptoalgebra/v1-core` only declares
///      `poolByPair`. Custom Algebra pools (deployed by a registered custom pool deployer,
///      e.g. Hydrex's NAV/RWA plugin factory) are absent from `poolByPair` and are instead
///      keyed in a separate registry by the deployer that created them. This interface
///      declares only that one extra view so `VoterV5_GaugeLogic` can validate a custom-pool
///      ALM vault without pulling in a newer Algebra dependency.
interface IAlgebraFactoryCustom {
    /// @notice Returns the custom pool for a given deployer and token pair.
    /// @param deployer The custom pool deployer that created the pool.
    /// @param tokenA One of the pool's tokens (order-independent).
    /// @param tokenB The other pool token (order-independent).
    /// @return customPool The custom pool address, or address(0) if none exists.
    function customPoolByPair(
        address deployer,
        address tokenA,
        address tokenB
    ) external view returns (address customPool);
}
