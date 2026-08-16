// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./IEmissionSchedule.sol";
import "../libraries/Math.sol";
import "../Constants.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title RevisedPhasedEmissionSchedule
 * @notice Hydrex community proposal emission schedule tuned for earlier, lower peak emissions
 * - Peak 1.2% at week 12, then linear decline of 0.02%/week to 0.4% at week 52
 * - Post-bootstrap tail starts at 0.4% with governance-controlled ±0.02% adjustments
 * @dev Governance is managed via the `governance` address and `onlyGovernance` modifier
 */
contract RevisedPhasedEmissionSchedule is IEmissionSchedule, ERC165 {
    /**
     * @notice Percentage precision for emission rates
     * 100e16 = 100%
     * 10e16  = 10%
     * 1e16   = 1%
     * 1e15   = 0.1%
     * 1e14   = 0.01%
     * 1e13   = 0.001%
     * 1e12   = 0.0001%
     */
    uint256 public constant PERCENT_PRECISION = 1e18;
    uint256 private constant _26_PERCENT = 26e16;
    uint256 private constant _POINT_5_PERCENT = 5e15;
    uint256 private constant _POINT_1_PERCENT = 1e15;
    uint256 private constant _POINT_02_PERCENT = 2e14;

    /**
     * @notice Emission Slope Increase
     * - Week 0 - Week 12
     */
    uint256 public constant INITIAL_RATE = 0;
    uint256 public constant SLOPE_INCREASE_RATE_PER_WEEK = _POINT_1_PERCENT; // +0.10% weekly
    uint256 public constant SLOPE_INCREASE_END_WEEK = 12;
    uint256 public constant SLOPE_INCREASE_PEAK_RATE =
        INITIAL_RATE + (SLOPE_INCREASE_RATE_PER_WEEK * SLOPE_INCREASE_END_WEEK); // 1.2%

    /**
     * @notice Emission Slope Decline
     * - Week 13 - Week 52
     */
    uint256 public constant SLOPE_DECLINE_RATE_PER_WEEK = _POINT_02_PERCENT; // -0.02% weekly
    uint256 public constant SLOPE_DECLINE_END_WEEK = 52;

    /**
     * @notice After Bootstrap Emission Schedule
     * - Week 53 - Infinity
     */
    uint256 public constant POST_BOOTSTRAP_MAX_ADJUSTMENT_RATE = _POINT_02_PERCENT;
    uint256 public constant POST_BOOTSTRAP_MAX_RATE = 2e16; // 2% maximum tail emission rate
    uint256 public postBootstrapRate; // Computed in constructor (starts at 0.4%)

    /**
     * @notice Rebase Parameters (unchanged from v1)
     */
    uint256 public constant INITIAL_REBASE_RATE = _26_PERCENT;
    uint256 public constant REBASE_DECAY_RATE = _POINT_5_PERCENT;
    uint256 public constant MINIMUM_REBASE_RATE = 0; // 0% minimum rebase
    uint256 public constant REBASE_END_WEEK = 52; // 1 year until minimum

    /// @notice Governance address
    address public governance;

    /// @notice Epoch number (block.timestamp / Constants.EPOCH) of last tail emission adjustment
    uint256 public lastTailAdjustmentUnixEpoch;

    error PhasedEmissionSchedule__SlopeDeclineRateTotalTooHigh();
    error PhasedEmissionSchedule__SlopeIncreaseEndWeekAfterSlopeDeclineEndWeek();
    error PhasedEmissionSchedule__NotGovernance();
    error PhasedEmissionSchedule__PostBootstrapRateAdjustmentTooHigh();
    error PhasedEmissionSchedule__PostBootstrapRateExceedsMaximum();
    error PhasedEmissionSchedule__PostBootstrapRateAdjustmentExceedsCurrentRate(uint256 currentRate, uint256 adjustment);
    error PhasedEmissionSchedule__TailEmissionAlreadyAdjustedThisEpoch(uint256 epoch);
    error PhasedEmissionSchedule__ZeroAddress();

    event TailEmissionAdjusted(uint256 indexed epoch, uint256 newRate, uint256 adjustment, bool increased);
    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address _governance) {
        if (_governance == address(0)) {
            revert PhasedEmissionSchedule__ZeroAddress();
        }
        
        if (SLOPE_INCREASE_END_WEEK > SLOPE_DECLINE_END_WEEK) {
            revert PhasedEmissionSchedule__SlopeIncreaseEndWeekAfterSlopeDeclineEndWeek();
        }

        // Verify emission slope isn't too aggressive
        uint256 slopeDeclineRateTotal = ((SLOPE_DECLINE_END_WEEK - SLOPE_INCREASE_END_WEEK) *
            SLOPE_DECLINE_RATE_PER_WEEK);
        if (slopeDeclineRateTotal > SLOPE_INCREASE_PEAK_RATE) {
            revert PhasedEmissionSchedule__SlopeDeclineRateTotalTooHigh();
        }
        postBootstrapRate = SLOPE_INCREASE_PEAK_RATE - slopeDeclineRateTotal; // 0.4% starting tail

        governance = _governance;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IEmissionSchedule).interfaceId || super.supportsInterface(interfaceId);
    }

    /// -----------------------------------------------------------------------
    /// Admin Functions
    /// -----------------------------------------------------------------------

    modifier onlyGovernance() {
        if (msg.sender != governance) {
            revert PhasedEmissionSchedule__NotGovernance();
        }
        _;
    }

    /**
     * @notice Adjust tail emission
     * @param _postBootstrapRateAdjustment Amount to adjust tail emission by
     * @param increase Whether to increase or decrease tail emission
     */
    function adjustTailEmission(uint256 _postBootstrapRateAdjustment, bool increase) external onlyGovernance {
        uint256 unixEpoch = block.timestamp / Constants.EPOCH;
        if (unixEpoch == lastTailAdjustmentUnixEpoch) {
            revert PhasedEmissionSchedule__TailEmissionAlreadyAdjustedThisEpoch(unixEpoch);
        }
        lastTailAdjustmentUnixEpoch = unixEpoch;

        if (_postBootstrapRateAdjustment > POST_BOOTSTRAP_MAX_ADJUSTMENT_RATE) {
            revert PhasedEmissionSchedule__PostBootstrapRateAdjustmentTooHigh();
        }

        if (increase) {
            uint256 newRate = postBootstrapRate + _postBootstrapRateAdjustment;
            if (newRate > POST_BOOTSTRAP_MAX_RATE) {
                revert PhasedEmissionSchedule__PostBootstrapRateExceedsMaximum();
            }
            postBootstrapRate = newRate;
        } else {
            if (_postBootstrapRateAdjustment > postBootstrapRate) {
                revert PhasedEmissionSchedule__PostBootstrapRateAdjustmentExceedsCurrentRate(
                    postBootstrapRate,
                    _postBootstrapRateAdjustment
                );
            }
            postBootstrapRate -= _postBootstrapRateAdjustment;
        }

        emit TailEmissionAdjusted(unixEpoch, postBootstrapRate, _postBootstrapRateAdjustment, increase);
    }

    /**
     * @notice Transfer governance to a new address
     * @param _newGovernance The new governance address
     */
    function transferGovernance(address _newGovernance) external onlyGovernance {
        if (_newGovernance == address(0)) {
            revert PhasedEmissionSchedule__ZeroAddress();
        }
        address previousGovernance = governance;
        governance = _newGovernance;
        emit GovernanceTransferred(previousGovernance, _newGovernance);
    }

    /// -----------------------------------------------------------------------
    /// MinterV3 Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IEmissionSchedule
    function calculateWeeklyEmission(
        uint256 weekNumber, // Weeks since schedule start (relative)
        uint256 totalSupply
    ) external view returns (uint256 emissionAmount) {
        // Revised 3-phase emission with earlier/lower peak then controlled decline
        /// @dev After bootstrap phase
        if (weekNumber > SLOPE_DECLINE_END_WEEK) {
            emissionAmount = (totalSupply * postBootstrapRate) / PERCENT_PRECISION;
            return emissionAmount;
        }

        /// @dev Slope Decline Phase
        if (weekNumber > SLOPE_INCREASE_END_WEEK) {
            uint256 weeksAfterPeak = weekNumber - SLOPE_INCREASE_END_WEEK;
            uint256 declineRate = SLOPE_INCREASE_PEAK_RATE - (SLOPE_DECLINE_RATE_PER_WEEK * weeksAfterPeak);
            emissionAmount = (totalSupply * declineRate) / PERCENT_PRECISION;
            return emissionAmount;
        }

        /// @dev Slope Increase Phase, assumes weekNumber is 0-indexed
        uint256 increaseRate = INITIAL_RATE + (weekNumber * SLOPE_INCREASE_RATE_PER_WEEK);
        emissionAmount = (totalSupply * increaseRate) / PERCENT_PRECISION;
        return emissionAmount;
    }

    /// @inheritdoc IEmissionSchedule
    function calculateRebaseAmount(
        uint256 weekNumber,
        uint256 weeklyEmission,
        uint256 veSupply,
        uint256 totalSupply
    ) external pure returns (uint256 rebaseAmount) {
        // Guard against division by zero
        if (totalSupply == 0) {
            return 0;
        }

        // Calculate rebase rate based on week number
        if (weekNumber >= REBASE_END_WEEK) {
            return 0;
        }

        uint256 currentRebaseRate;
        uint256 totalDecay = weekNumber * REBASE_DECAY_RATE;
        if (totalDecay >= INITIAL_REBASE_RATE - MINIMUM_REBASE_RATE) {
            currentRebaseRate = MINIMUM_REBASE_RATE;
        } else {
            currentRebaseRate = INITIAL_REBASE_RATE - totalDecay;
        }

        // Calculate rebase amount based on locked share and current rate
        uint256 lockedShare = (veSupply * PERCENT_PRECISION) / totalSupply;
        /// @dev Cap rebase by the smaller of lockedShare or currentRebaseRate
        if (lockedShare < currentRebaseRate) {
            return (weeklyEmission * lockedShare) / PERCENT_PRECISION;
        } else {
            return (weeklyEmission * currentRebaseRate) / PERCENT_PRECISION;
        }
    }
}
