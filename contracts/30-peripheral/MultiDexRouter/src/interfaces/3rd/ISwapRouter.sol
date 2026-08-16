// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev This is a stripped version of the Uniswap SwapRouter02 interface
/// https://github.com/Uniswap/swap-router-contracts/blob/v1.3.0/contracts/SwapRouter02.sol
/// In the context of PancakeSwap, it is named as SmartRouter:
/// https://bscscan.com/address/0x13f4EA83D0bd40E75C8222255bc855a974568Dd4#code
interface ISwapRouter {
    //
    // V2 related functions
    //

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @dev Setting `amountIn` to 0 will cause the contract to look up its own balance,
    /// and swap the entire amount, enabling contracts to send tokens before calling this function.
    /// When the path[0] is WETH and msg.value is greater than 0, the contract will wrap the msg.value into WETH.
    /// @param amountIn The amount of token to swap
    /// @param amountOutMin The minimum amount of output that must be received
    /// @param path The ordered list of tokens to swap through
    /// @param to The recipient address
    /// @return amountOut The amount of the received token
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to)
        external
        payable
        returns (uint256 amountOut);

    //
    // v3 related functions
    //
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @dev Setting `amountIn` to 0 will cause the contract to look up its own balance,
    /// and swap the entire amount, enabling contracts to send tokens before calling this function.
    /// Similar to `swapExactTokensForTokens`, if the `tokenIn` is WETH and `msg.value` is greater than 0,
    /// the contract will wrap the `msg.value` into WETH.
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @dev Setting `amountIn` to 0 will cause the contract to look up its own balance,
    /// and swap the entire amount, enabling contracts to send tokens before calling this function.
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    //
    // misc
    //

    /// @notice Transfers the full amount of a token held by this contract to recipient
    /// @dev The amountMinimum parameter prevents malicious contracts from stealing the token from users
    /// @param token The contract address of the token which will be transferred to `recipient`
    /// @param amountMinimum The minimum amount of token required for a transfer
    /// @param recipient The destination address of the token
    function sweepToken(address token, uint256 amountMinimum, address recipient) external payable;

    /// @notice Call multiple functions in the current contract and return the data from all of them if they all succeed
    /// @dev The `msg.value` should not be trusted for any method callable from multicall.
    /// @param data The encoded function data for each of the calls to make to this contract
    /// @return results The results from each of the calls passed in via data
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    /// @notice Unwraps the contract's WETH9 balance and sends it to recipient as ETH.
    /// @dev The amountMinimum parameter prevents malicious contracts from stealing WETH9 from users.
    /// @param amountMinimum The minimum amount of WETH9 to unwrap
    /// @param recipient The address receiving ETH
    function unwrapWETH9(uint256 amountMinimum, address recipient) external payable;
}

/// @title Constant state
/// @notice Constant state used by the swap router
library SwapRouterConstants {
    /// @dev Used for identifying cases when this contract's balance of a token is to be used
    uint256 internal constant CONTRACT_BALANCE = 0;

    /// @dev Used as a flag for identifying address(this), saves gas by sending more 0 bytes
    address internal constant ADDRESS_THIS = address(2);
}
