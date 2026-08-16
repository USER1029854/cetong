// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./libraries/Math.sol";
import "./interfaces/IMinter.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/IProtocolToken.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IVersionable.sol";
import "./emission-schedule/IEmissionSchedule.sol";
import "./VoterV5/VotingEscrow/IVotingEscrowV2.sol";
import "./VoterV5/VotingEscrow/IVotingEscrowV2_Data.sol";

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "./Constants.sol";

/**
 * @title MinterUpgradeableV4
 * @notice V4 splits the `team` storage slot into two roles:
 *   - teamRecipient: address that receives the 4% weekly team emission (slot 207, reused from V3 `team`)
 *   - teamAdmin:     address that gates all admin setter calls (slots 218–219, new)
 *
 * @dev Storage layout (slots 207–219):
 *   207: teamRecipient  (was: team)
 *   208: pendingTeamRecipient  (was: pendingTeam)
 *   217: emissionsGovernor  (unchanged)
 *   218: teamAdmin  (NEW — from __gap)
 *   219: pendingTeamAdmin  (NEW — from __gap)
 *   220–263: __gap[44]  (was __gap[46])
 *
 * Changes from V3:
 *   - `team` renamed to `teamRecipient`; `pendingTeam` renamed to `pendingTeamRecipient`
 *   - `teamAdmin` and `pendingTeamAdmin` added (two-step, mirrors governor pattern)
 *   - setVoter, setEmissionsGovernor, setRewardDistributor now gated by teamAdmin
 *   - setTeamRecipient (two-step) replaces setTeam, gated by teamAdmin
 *   - setTeamAdmin (two-step) added, gated by current teamAdmin
 *   - reinitializeV4 reinitializer sets teamRecipient and teamAdmin on upgrade
 *
 * @dev Invariant: __gap length is [44]. Two slots (teamAdmin, pendingTeamAdmin) were added in v4;
 *      any further storage additions MUST decrement __gap by the same number of slots.
 */
contract MinterUpgradeableV4 is IMinter, IVersionable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    string public constant override VERSION = "4.0.0";
    uint256 private constant _NOT_INITIALIZED_TIMESTAMP = type(uint256).max;
    address private constant _INITIALIZED_ADDRESS = address(1);

    uint public constant PRECISION = 1000;
    uint public teamRate;
    uint public constant MAX_TEAM_RATE = 50; // 5%

    uint public WEEK = Constants.EPOCH;
    uint public weekly;
    uint public active_period;
    uint public initial_period_start;
    uint public constant LOCK = 86400 * 7 * 52 * 2;

    address internal _initializer;

    // -------------------------------------------------------------------------
    // Slot 207 (was: team) — receives 4% weekly emissions
    // -------------------------------------------------------------------------
    address public teamRecipient;

    // -------------------------------------------------------------------------
    // Slot 208 (was: pendingTeam) — pending two-step change of teamRecipient
    // -------------------------------------------------------------------------
    address public pendingTeamRecipient;

    address public governor;
    address public pendingGovernor;

    IProtocolToken public protocolToken;
    IVoter public _voter;
    IVotingEscrowV2 public _ve;
    IRewardsDistributor public _rewards_distributor;
    IEmissionSchedule public emissionSchedule;

    bool public useInitialSupply;
    uint256 public initialSupply;

    address public emissionsGovernor;

    // -------------------------------------------------------------------------
    // Slots 218–219 (NEW — taken from __gap)
    // -------------------------------------------------------------------------
    /// @notice Gates all onlyTeam admin calls. Initially set to TimelockController.
    address public teamAdmin;
    address public pendingTeamAdmin;

    // @dev Invariant: __gap length is [44]. teamAdmin + pendingTeamAdmin (2 slots) added in v4.
    uint256[44] private __gap;

    // =========================================================================
    // Events
    // =========================================================================

    event Mint(address indexed sender, uint weekly_emission, uint circulating_supply, uint week_number);
    event SetGovernor(address newGovernor);
    event SetTeamRecipient(address newTeamRecipient);
    event SetTeamAdmin(address newTeamAdmin);
    event SetVoter(address newVoter);
    event SetTeamRate(uint256 newRate);
    event SetEmissionSchedule(address oldSchedule, address newSchedule);
    event SetInitialSupply(uint256 newInitialSupply);

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor() {
        _disableInitializers();
    }

    // =========================================================================
    // Initializer (V3-compatible; used for fresh deployments only)
    // =========================================================================

    function initialize(
        address __voter,
        address __ve,
        address __rewards_distributor,
        address __emission_schedule,
        bool __useInitialSupply
    ) initializer public {
        __Ownable_init();

        _initializer = msg.sender;
        teamRecipient = msg.sender;
        teamAdmin = msg.sender;
        governor = msg.sender;

        teamRate = 40; // 400 bps = 4%
        WEEK = Constants.EPOCH;

        protocolToken = IProtocolToken(address(IVotingEscrowV2(__ve).token()));
        _voter = IVoter(__voter);
        _ve = IVotingEscrowV2(__ve);
        _rewards_distributor = IRewardsDistributor(__rewards_distributor);
        _setEmissionSchedule(__emission_schedule);
        useInitialSupply = __useInitialSupply;

        active_period = _NOT_INITIALIZED_TIMESTAMP;
        initial_period_start = _NOT_INITIALIZED_TIMESTAMP;
    }

    // =========================================================================
    // Reinitializer — called via upgradeAndCall when upgrading from V3 → V4
    // =========================================================================

    /// @notice Upgrade initializer: splits the former `team` slot into distinct roles.
    /// @dev Called by ProxyAdmin.upgradeAndCall. Sets teamRecipient and teamAdmin from
    ///      the V3 `team` slot value, which held the Admin Safe address.
    ///      Precondition: teamRecipient slot (207) holds the V3 team address (Admin Safe).
    ///      Postcondition: teamRecipient = _teamRecipient, teamAdmin = _teamAdmin.
    /// @param _teamRecipient Address to receive 4% weekly emissions (Treasury Safe)
    /// @param _teamAdmin     Address to gate all onlyTeam admin calls (TimelockController)
    function reinitializeV4(address _teamRecipient, address _teamAdmin) external reinitializer(2) {
        require(_teamRecipient != address(0), "MinterV4: zero teamRecipient");
        require(_teamAdmin != address(0), "MinterV4: zero teamAdmin");
        teamRecipient = _teamRecipient;
        teamAdmin = _teamAdmin;
        // Zero any pending two-step changes that may have been in-flight at upgrade time.
        // Prevents a pendingTeam value (V3 slot 208) from being accepted as pendingTeamRecipient.
        pendingTeamRecipient = address(0);
        pendingTeamAdmin = address(0);
        emit SetTeamRecipient(_teamRecipient);
        emit SetTeamAdmin(_teamAdmin);
    }

    // =========================================================================
    // Admin — governor-gated
    // =========================================================================

    function setGovernor(address _governor) external {
        require(msg.sender == governor, "not governor");
        pendingGovernor = _governor;
        emit SetGovernor(pendingGovernor);
    }

    function acceptGovernor() external {
        require(msg.sender == pendingGovernor, "not pending governor");
        governor = pendingGovernor;
        pendingGovernor = address(0);
        emit SetGovernor(governor);
    }

    function setTeamRate(uint _teamRate) external {
        require(msg.sender == governor, "not governor");
        require(_teamRate <= MAX_TEAM_RATE, "teamRate too high");
        teamRate = _teamRate;
        emit SetTeamRate(teamRate);
    }

    function setEmissionSchedule(address _schedule) external {
        require(msg.sender == governor, "not governor");
        _setEmissionSchedule(_schedule);
    }

    // =========================================================================
    // Admin — teamAdmin-gated
    // =========================================================================

    function setTeamRecipient(address _teamRecipient) external {
        require(msg.sender == teamAdmin, "MinterV4: not teamAdmin");
        require(_teamRecipient != address(0), "MinterV4: zero address");
        pendingTeamRecipient = _teamRecipient;
        emit SetTeamRecipient(_teamRecipient);
    }

    function acceptTeamRecipient() external {
        require(msg.sender == pendingTeamRecipient, "MinterV4: not pending teamRecipient");
        teamRecipient = pendingTeamRecipient;
        pendingTeamRecipient = address(0);
        emit SetTeamRecipient(teamRecipient);
    }

    function setTeamAdmin(address _teamAdmin) external {
        require(msg.sender == teamAdmin, "MinterV4: not teamAdmin");
        require(_teamAdmin != address(0), "MinterV4: zero address");
        pendingTeamAdmin = _teamAdmin;
        emit SetTeamAdmin(_teamAdmin);
    }

    function acceptTeamAdmin() external {
        require(msg.sender == pendingTeamAdmin, "MinterV4: not pending teamAdmin");
        teamAdmin = pendingTeamAdmin;
        pendingTeamAdmin = address(0);
        emit SetTeamAdmin(teamAdmin);
    }

    function setVoter(address __voter) external {
        require(__voter != address(0), "MinterV4: zero address");
        require(msg.sender == teamAdmin, "MinterV4: not teamAdmin");
        _voter = IVoter(__voter);
        emit SetVoter(__voter);
    }

    event SetEmissionsGovernor(address indexed oldEmissionsGovernor, address indexed newEmissionsGovernor);

    function setEmissionsGovernor(address _emissionsGovernor) external {
        require(msg.sender == teamAdmin, "MinterV4: not teamAdmin");
        emit SetEmissionsGovernor(emissionsGovernor, _emissionsGovernor);
        emissionsGovernor = _emissionsGovernor;
    }

    function setRewardDistributor(address _rewardDistro) external {
        require(msg.sender == teamAdmin, "MinterV4: not teamAdmin");
        _rewards_distributor = IRewardsDistributor(_rewardDistro);
    }

    // =========================================================================
    // Admin — onlyOwner
    // =========================================================================

    function setInitialSupply(uint256 _initialSupply) external onlyOwner {
        initialSupply = _initialSupply;
        emit SetInitialSupply(_initialSupply);
    }

    // =========================================================================
    // Protocol init (governor-gated, one-time)
    // =========================================================================

    function _initialize(
        address[] memory claimants,
        uint[] memory amounts,
        uint max
    ) external {
        require(governor == msg.sender, 'not governor');
        require(_initializer != address(0), 'already initialized');
        require(claimants.length == amounts.length, "Length missmatch");
        try protocolToken.acceptOwnership() {
        } catch {
            // Continue
        }
        if(max > 0) {
            uint256 sum;
            protocolToken.mint(address(this), max);
            protocolToken.approve(address(_ve), type(uint).max);
            for (uint i = 0; i < claimants.length; i++) {
                _ve.createLockFor(amounts[i], LOCK, claimants[i], IVotingEscrowV2_Data.LockType.PERMANENT);
                sum += amounts[i];
            }
            require(sum == max, "Incorrect max value");
        }

        if (useInitialSupply && initialSupply == 0) {
            initialSupply = protocolToken.totalSupply();
            emit SetInitialSupply(initialSupply);
        }

        _initializer = _INITIALIZED_ADDRESS;
        uint256 initialWeekStart = period();
        active_period = initialWeekStart;
        initial_period_start = initialWeekStart;
    }

    // =========================================================================
    // View / calculation
    // =========================================================================

    function circulating_supply() public view returns (uint) {
        return protocolToken.totalSupply() - protocolToken.balanceOf(address(_ve));
    }

    function getCurrentEpoch() public view returns (uint256) {
        return getCurrentWeek();
    }

    function getCurrentWeek() public view returns (uint256) {
        if (initial_period_start == _NOT_INITIALIZED_TIMESTAMP) {
            return 0;
        }
        return (active_period - initial_period_start) / WEEK;
    }

    function can_update_period() public view returns (bool) {
        return (block.timestamp >= active_period + WEEK && _initializer == _INITIALIZED_ADDRESS);
    }

    function weekly_emission() public view returns (uint) {
        if (initial_period_start == _NOT_INITIALIZED_TIMESTAMP) return 0;
        uint256 supplyForCalculation = useInitialSupply && initialSupply > 0 ? initialSupply : protocolToken.totalSupply();
        return emissionSchedule.calculateWeeklyEmission(getCurrentWeek(), supplyForCalculation);
    }

    function calculate_rebase(uint _weeklyMint) public view returns (uint) {
        if (initial_period_start == _NOT_INITIALIZED_TIMESTAMP) return 0;
        uint256 supplyForCalculation = useInitialSupply && initialSupply > 0 ? initialSupply : protocolToken.totalSupply();
        return emissionSchedule.calculateRebaseAmount(getCurrentWeek(), _weeklyMint, _ve.supply(), supplyForCalculation);
    }

    // =========================================================================
    // Core minting
    // =========================================================================

    function update_period() external override nonReentrant returns (uint current_period) {
        current_period = period();
        if (can_update_period()) {
            active_period = current_period;

            // Auto-execute last epoch's emission signal (silent skip if quorum not met or already executed)
            // @dev The try/catch is intentional: EmissionsGovernor failures must NEVER block minting.
            address _emissionsGovernor = emissionsGovernor;
            if (_emissionsGovernor != address(0)) {
                // solhint-disable-next-line no-empty-blocks
                try IEmissionsGovernorMinimalV4(_emissionsGovernor).tryExecuteSignal() {} catch {}
            }

            if (useInitialSupply && initialSupply == 0) {
                initialSupply = protocolToken.totalSupply();
            }

            weekly = weekly_emission();
            uint _required = weekly;

            uint _rebase = calculate_rebase(weekly);
            uint _teamEmissions = weekly * teamRate / PRECISION;
            uint _gauge = weekly - _rebase - _teamEmissions;

            uint _balanceOf = protocolToken.balanceOf(address(this));
            if (_balanceOf < _required) {
                protocolToken.mint(address(this), _required - _balanceOf);
            }

            require(protocolToken.transfer(teamRecipient, _teamEmissions));
            require(protocolToken.transfer(address(_rewards_distributor), _rebase));
            _rewards_distributor.checkpoint_token();
            _rewards_distributor.checkpoint_total_supply();
            protocolToken.approve(address(_voter), _gauge);
            _voter.notifyRewardAmount(_gauge);

            emit Mint(msg.sender, weekly, circulating_supply(), getCurrentWeek());
        }
        return current_period;
    }

    // =========================================================================
    // Backwards compat
    // =========================================================================

    function check() external view override returns(bool) {
        return can_update_period();
    }

    function period() public view override returns(uint) {
        return (block.timestamp / WEEK) * WEEK;
    }

    // =========================================================================
    // Internal
    // =========================================================================

    function _setEmissionSchedule(address _schedule) private {
        bool isValidInterface = ERC165Checker.supportsInterface(_schedule, type(IEmissionSchedule).interfaceId);
        require(isValidInterface, "invalid schedule");
        emit SetEmissionSchedule(address(emissionSchedule), _schedule);
        emissionSchedule = IEmissionSchedule(_schedule);
    }
}

// =========================================================================
// Minimal interface — avoids circular import with EmissionsGovernor
// =========================================================================
interface IEmissionsGovernorMinimalV4 {
    function tryExecuteSignal() external;
}
