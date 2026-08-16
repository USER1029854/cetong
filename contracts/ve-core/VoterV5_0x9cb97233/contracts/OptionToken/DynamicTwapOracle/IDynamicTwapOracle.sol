// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.0;

interface IDynamicTwapOracle {
    /**
     * @notice Get the address of the pool
     * @return The address of the pool
     */
    function pool() external view returns (address);

    /**
     * @notice Get the address of the first token in the pool
     * @return The address of the first token
     */
    function token0() external view returns (address);
    
    /**
     * @notice Get the address of the second token in the pool
     * @return The address of the second token
     */
    function token1() external view returns (address);

    /**
     * @notice Estimate the output amount of a trade
     * @param tokenIn The address of the input token
     * @param amountIn The amount of the input token
     * @param secondsAgo The number of seconds ago to start the TWAP
     * @return amountOut The estimated output amount
     */
    function estimateAmountOut(
        address tokenIn,
        uint128 amountIn,
        uint32 secondsAgo
    ) external view returns (uint amountOut);
}