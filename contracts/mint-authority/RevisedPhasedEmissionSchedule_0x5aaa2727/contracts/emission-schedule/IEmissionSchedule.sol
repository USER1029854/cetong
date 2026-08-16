// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IEmissionSchedule
 * @notice Interface for configurable emission schedules
 * @dev Implementations should handle different emission patterns like bootstrap, stabilize, etc.
 */
interface IEmissionSchedule is IERC165 {

    /**
     * @notice Calculate weekly emission amount based on current week and supply metrics
     * @param weekNumber Number of weeks since schedule start (0-based)
     * @param totalSupply Current total supply of protocol token
     * @return weeklyEmission Amount of tokens to emit this week
     */
    function calculateWeeklyEmission(
        uint256 weekNumber,
        uint256 totalSupply
    ) external view returns (uint256 weeklyEmission);


    /**
     * @notice Calculate rebase amount for the current week
     * @param weekNumber Number of weeks since schedule start (0-based)
     * @param weeklyEmission Total emission amount for the week
     * @param veSupply Current voting escrow locked supply
     * @param totalSupply Current total supply
     * @return rebaseAmount Amount of weekly emission to be used for rebase
     */
    function calculateRebaseAmount(
        uint256 weekNumber,
        uint256 weeklyEmission,
        uint256 veSupply,
        uint256 totalSupply
    ) external view returns (uint256 rebaseAmount);
}
