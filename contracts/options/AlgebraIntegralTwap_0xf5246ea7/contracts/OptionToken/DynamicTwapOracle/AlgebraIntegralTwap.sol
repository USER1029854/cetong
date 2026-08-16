// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {IAlgebraFactory} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraFactory.sol";
import {TickMath} from "@cryptoalgebra/integral-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@cryptoalgebra/integral-core/contracts/libraries/FullMath.sol";
import {IDynamicTwapOracle} from "./IDynamicTwapOracle.sol";
import {IVolatilityOracle} from "@cryptoalgebra/integral-base-plugin/contracts/interfaces/plugins/IVolatilityOracle.sol";

contract AlgebraIntegralTwap is IDynamicTwapOracle {
    address public immutable override pool;
    address public immutable override token0;
    address public immutable override token1;

    constructor(address _factory, address _token0, address _token1) {
        address _pool = IAlgebraFactory(_factory).poolByPair(_token0, _token1);
        require(_pool != address(0), "pool doesn't exist");
        pool = _pool;
        (token0, token1) = _token0 < _token1 ? (_token0, _token1) : (_token1, _token0);
    }

    function estimateAmountOut(
        address tokenIn,
        uint128 amountIn,
        uint32 secondsAgo
    ) external view override returns (uint amountOut) {
        require(tokenIn == token0 || tokenIn == token1, "invalid token");
        address tokenOut = tokenIn == token0 ? token1 : token0;

        int24 timeWeightedAverageTick = _getTimeWeightedAverageTick(secondsAgo);

        amountOut = getQuoteAtTick(timeWeightedAverageTick, amountIn, tokenIn, tokenOut);
    }

    function _getTimeWeightedAverageTick(uint32 secondsAgo) internal view returns (int24 twapTick) {
        require(secondsAgo != 0, "secondsAgo must be > 0");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        address oracle = IAlgebraPool(pool).plugin();
        require(oracle != address(0), "oracle plugin not set");
        (int56[] memory tickCumulatives, ) = IVolatilityOracle(oracle).getTimepoints(secondsAgos);

        int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
        twapTick = int24(tickDelta / int56(uint56(secondsAgo)));
    }

    // Math helpers (adapted from Uniswap/Algebra)
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        if (baseToken < quoteToken) {
            quoteAmount = FullMath.mulDiv(uint256(sqrtRatioX96) * uint256(sqrtRatioX96), baseAmount, 1 << 192);
        } else {
            quoteAmount = FullMath.mulDiv(1 << 192, baseAmount, uint256(sqrtRatioX96) * uint256(sqrtRatioX96));
        }
    }
}
