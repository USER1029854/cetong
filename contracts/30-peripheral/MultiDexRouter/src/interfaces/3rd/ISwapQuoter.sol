// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Quoter for quoting exact input swaps on Uniswap-like V3 pools.
/// @dev This is a stripped version of the Uniswap QuoterV2 interface
/// https://github.com/Uniswap/v3-periphery/blob/main/contracts/lens/QuoterV2.sol
/// Or the equivalent PancakeSwap QuoterV2 interface:
/// https://vscode.blockscan.com/56/0xB048Bbc1Ee6b733FFfCFb9e9CeF7375518e25997
interface IV3Quoter {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleParams`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountIn The desired input amount
    /// sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
    /// @return amountOut The amount of `tokenOut` that would be received
    /// @return sqrtPriceX96After The sqrt price of the pool after the swap
    /// @return initializedTicksCrossed The number of initialized ticks that the swap crossed
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

/// @notice Quoter for quoting exact input swaps on Uniswap-like V2 pools
/// @dev This is a stripped version of the Uniswap Router https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol
/// or the equivalent PancakeSwap Router interface:
/// https://bscscan.com/address/0x10ed43c718714eb63d5aa57b78b54704e256024e#code
interface IV2Quoter {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountOut);
}
