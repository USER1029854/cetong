/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PoolKey } from "./PoolKey.sol";

// import {IImmutableState} from "@uniswap/v4-periphery/src/interfaces/IImmutableState.sol";
interface IImmutableState {
    /// @notice The Uniswap v4 PoolManager contract
    function poolManager() external view returns (address /*IPoolManager*/);
}

/**
 * @title IMultiPositionManager
 * @author Gamma
 * @notice This interface is used to interact with Gamma ALM strategies which use UniswapV4 pools as concentrated liquidity positions.
 */
interface IMultiPositionManager is IERC20, IImmutableState {
  struct Position {
    PoolKey poolKey;
    int24 lowerTick;
    int24 upperTick;
  }

  struct PositionData {
    uint128 liquidity;
    uint256 amount0;
    uint256 amount1;
  }
  function getPositions() external view returns (
      Position[] memory,
      PositionData[] memory
  );
  function basePositionsLength() external view returns (uint256);
  function token0() external view returns (IERC20);
  function token1() external view returns (IERC20);
  function getTotalAmounts() external view returns (
    uint256 total0,
    uint256 total1,
    uint256 totalFee0,
    uint256 totalFee1
  );
  function currentTicks() external view returns (int24[] memory);
  function rebalance(
    Position[] memory baseRanges,
    uint128[] memory liquidities,
    int24 limitWidth,
    uint256[2][] memory inMin,
    uint256[2][] memory outMin,
    int24 aimTick,
    uint24 tickOffset
  ) external;
  function compound(
    uint128[] memory liquidities,
    uint256[2][] memory inMin,
    int24 aimTick,
    uint24 tickOffset
  ) external;
  function claimFee() external;
  function setWhitelist(address _whitelist) external;
  function setFeeRecipient(address _feeRecipient) external;
  function setFee(uint16 fee) external;
  // function setTickOffset(uint24 offset) external;
  function deposit(
    uint256 deposit0Desired,
    uint256 deposit1Desired,
    address to,
    address from
  ) external payable returns (uint256, uint256, uint256);
  function zeroBurnAll() external;
  
}
