// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// Package Imports
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Local Imports
import {IVoterV5_Logic} from "./IVoterV5_Logic.sol";
import {IBribe} from "./IBribe.sol";
import {IGauge} from "../interfaces/IGauge.sol";
import {IOptionTokenV4} from "../OptionToken/IOptionTokenV4.sol";
import {IMinter} from "../interfaces/IMinter.sol";
import {IPermissionsRegistry} from "../interfaces/IPermissionsRegistry.sol";
import {IVoterV5_GaugeLogic} from "./VoterV5_GaugeLogic.sol";
import {IVoterV5_ClaimLogic} from "./IVoterV5_ClaimLogic.sol";
import {Constants} from "../Constants.sol";
import {VoterV5_Storage} from "./VoterV5_Storage.sol";
import {IVotingEscrowV2} from "./VotingEscrow/IVotingEscrowV2.sol";
import {DelegateCallLib} from "../libraries/DelegateCallLib.sol";

/**
 * @title VoterV5
 * @notice VoterV5 allows users to vote on gauges/pools through a VotingEscrow position and receive rewards.
 * @dev
 *  - DOES NOT support fee-on-transfer tokens for the `base` reward token or Option Tokens.
 *  - WARN `setOptionsToken` can change the distribution token if invoked before the EPOCH flip. It is highly recommended
 *      to call this function AFTER the EPOCH flip to avoid any confusion.
 */
contract VoterV5 is IVoterV5_Logic, VoterV5_Storage, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    EVENTS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    event GaugeCreated(
        address indexed gauge,
        address creator,
        address internal_bribe,
        address indexed external_bribe,
        address indexed pool
    );
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event Voted(address indexed voter, uint256 weight);
    event Abstained(address voter, uint256 weight);
    event NotifyReward(address indexed sender, address indexed reward, uint256 amount);
    event DistributeReward(address indexed sender, address indexed gauge, uint256 amount);
    event RefundReward(address indexed gauge, uint256 amount);
    event Whitelisted(address indexed whitelister, address indexed token);
    event Blacklisted(address indexed blacklister, address indexed token);
    event WhitelistedPool(address indexed whitelister, address indexed pool);
    event BlacklistedPool(address indexed blacklister, address indexed pool);
    event Attach(address indexed owner, address indexed gauge, uint256 tokenId);
    event Detach(address indexed owner, address indexed gauge, uint256 tokenId);

    event SetMinter(address indexed old, address indexed latest);
    event SetOptions(address indexed old, address indexed latest);
    event SetGaugeLogic(address indexed old, address indexed latest);
    event SetClaimLogic(address indexed old, address indexed latest);
    event HitRefreshApprovalLimit(uint256 fromGaugeIndex, uint256 toGaugeIndex);
    event SetDepositor(address indexed old, bool enabled);
    event SetBribeFactory(address indexed old, address indexed latest);
    event SetPairFactory(address indexed old, address indexed latest);
    event SetPermissionRegistry(address indexed old, address indexed latest);
    event SetGaugeFactory(address indexed old, address indexed latest);
    event SetBribeFor(bool isInternal, address indexed old, address indexed latest, address indexed gauge);
    event SetVoteDelay(uint256 old, uint256 latest);
    event AddFactories(address indexed pairfactory, address indexed gaugefactory);
    event FactoryEnabled(uint256 indexed gaugeType, address indexed pairFactory, address indexed gaugeFactory);
    event FactoryDisabled(uint256 indexed gaugeType, address indexed pairFactory, address indexed gaugeFactory);
    event FactoryReplaced(
        uint256 indexed gaugeType,
        address indexed oldPairFactory,
        address indexed oldGaugeFactory,
        address newPairFactory,
        address newGaugeFactory
    );

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ERRORS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    error AlreadyInitialized();
    error InvalidProtocolName();
    error NotVoterAdmin();
    error NotInfraAdmin();
    error NotVoterOrGaugeAdmin();
    error NotGovernance();
    error NotAuthorized();
    error InvalidDelay();
    error InvalidTokenAddress();
    error DelayAlreadySet();
    error AlreadyGaugeFactory();
    error NotGaugeLogic();
    error NotClaimLogic();
    error NotGaugeFactory();
    error NotFactory();
    error NotGauge();
    error GaugeAlreadyKilled();
    error GaugeAlreadyAlive();
    error ExceedsMaxGauges();
    error CannotReviveGaugeInSameEpoch();
    error NotApprovedOrOwner();
    error InsufficientVotingPower();
    error VoteDelayNotMet();
    error EpochStale();
    error EpochFlipInProgress();
    error VotedAlready();
    error LengthMismatch();
    error ZeroAddress();
    error NotContract();
    error InvalidGaugeType();
    error InconsistentFactoryPair();

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                            CONSTRUCTOR & INITIALIZER
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    constructor() {
        /// @dev Protecting the initializer on the implementation contract is important.
        /// A malicious actor could potentially self-destruct the implementation by setting a malicious gaugeLogic contract.
        _disableInitializers();
    }

    function initialize(
        address __ve,
        address _pairFactory,
        address _gaugeFactory,
        address _bribeFactory,
        address _gaugeLogic,
        address _claimLogic,
        string memory _protocolName
    ) public initializer {
        __ReentrancyGuard_init();

        _ve = __ve;
        base = address(IVotingEscrowV2(__ve).token());

        if (_pairFactory != address(0)) {
            _factories.push(_pairFactory);
            isFactory[_pairFactory]++;
        }

        if (_gaugeFactory != address(0)) {
            _gaugeFactories.push(_gaugeFactory);
            isGaugeFactory[_gaugeFactory]++;
        }

        bribefactory = _bribeFactory;

        minter = msg.sender;
        permissionRegistry = msg.sender;

        if (bytes(_protocolName).length == 0) {
            revert InvalidProtocolName();
        }
        protocolName = _protocolName;

        VOTE_DELAY = 0;
        DURATION = Constants.EPOCH;
        MAX_VOTE_DELAY = Constants.EPOCH;

        initflag = false;

        _setGaugeLogic(_gaugeLogic);
        _setClaimLogic(_claimLogic);
    }

    function getEpochDuration() external view returns (uint256) {
        return DURATION;
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    MODIFIERS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @dev Using function instead of modifier to save gas
    function VoterAdmin() private view {
        if (!IPermissionsRegistry(permissionRegistry).hasRole("VOTER_ADMIN", msg.sender)) {
            revert NotVoterAdmin();
        }
    }

    /// @dev Using function instead of modifier to save gas
    function Governance() private view {
        if (!IPermissionsRegistry(permissionRegistry).hasRole("GOVERNANCE", msg.sender)) {
            revert NotGovernance();
        }
    }

    /// @dev Using function instead of modifier to save gas
    function InfraAdmin() private view {
        if (!IPermissionsRegistry(permissionRegistry).hasRole("INFRA_ADMIN", msg.sender)) {
            revert NotInfraAdmin();
        }
    }

    /// @dev Using function instead of modifier to save gas
    function VoterOrGaugeAdmin() private view {
        IPermissionsRegistry pr = IPermissionsRegistry(permissionRegistry);
        if (!pr.hasRole("VOTER_ADMIN", msg.sender) && !pr.hasRole("GAUGE_ADMIN", msg.sender)) {
            revert NotVoterOrGaugeAdmin();
        }
    }

    /// @notice initialize the voter contract
    /// @param  _tokens array of tokens to whitelist
    /// @param  _minter the minter of the protocol token
    function _init(address[] memory _tokens, address _permissionsRegistry, address _minter, address _oToken) external {
        if (msg.sender != minter && !IPermissionsRegistry(permissionRegistry).hasRole("VOTER_ADMIN", msg.sender)) {
            revert NotAuthorized();
        }
        if (initflag) {
            revert AlreadyInitialized();
        }
        for (uint256 i = 0; i < _tokens.length; i++) {
            _updateWhitelistToken(_tokens[i], true);
        }
        minter = _minter;
        permissionRegistry = _permissionsRegistry;
        if (_oToken != address(0)) {
            oToken = _oToken;
            /// @dev base must be approved to mint option token.
            IERC20(base).approve(oToken, type(uint256).max);
        }
        isGaugeDepositor[oToken] = true;
        initflag = true;
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    VoterAdmin
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice set vote delay in seconds
    function setVoteDelay(uint256 _delay) external {
        VoterAdmin();
        if (_delay == VOTE_DELAY) {
            revert DelayAlreadySet();
        }
        if (_delay > MAX_VOTE_DELAY) {
            revert InvalidDelay();
        }
        emit SetVoteDelay(VOTE_DELAY, _delay);
        VOTE_DELAY = _delay;
    }

    /// @notice Set a new Minter
    function setMinter(address _minter) external {
        InfraAdmin();
        if (_minter == address(0)) {
            revert ZeroAddress();
        }
        if (_minter.code.length == 0) {
            revert NotContract();
        }
        emit SetMinter(minter, _minter);
        minter = _minter;
    }

    /// @notice Set options token
    /// @dev The base token can become the gauge reward token by setting oToken to address(0).
    ///      When pools.length > 100, only the first 100 approvals are refreshed here and
    ///      HitRefreshApprovalLimit is emitted. The remaining pools must be updated by a
    ///      VOTER_ADMIN caller via refreshApprovals(start, finish, oldOtoken) — this is a
    ///      two-step operational dependency: INFRA_ADMIN (TC, 24h) initiates, VOTER_ADMIN
    ///      (Ops Safe) completes the approval refresh for the tail.
    function setOptionsToken(address _oToken) external {
        InfraAdmin();
        /// @dev oToken can be set to address(0) to revert to base token
        if (_oToken != address(0) && _oToken.code.length == 0) {
            revert InvalidTokenAddress();
        }
        // Revoke old Options token approval
        address oldToken = oToken;
        if (oldToken != address(0)) IERC20(base).approve(oldToken, 0);
        isGaugeDepositor[oldToken] = false;
        // Set new Options token. Revert to `base` if _oToken is address(0)
        oToken = _oToken;
        emit SetOptions(oldToken, _oToken);
        /// @dev If oToken == address(0), the base token approves will be updated in refreshApprovals()
        if (_oToken != address(0)) {
            isGaugeDepositor[oToken] = true;
            IERC20(base).approve(oToken, type(uint256).max);
        }

        uint256 stop = pools.length;
        /// @dev this is to avoid gas limits. If this happens the function will need to be manually ran externally
        if (stop > 100) {
            stop = 100;
            emit HitRefreshApprovalLimit(0, stop);
        }
        if (pools.length > 0) _doRefreshApprovals(0, stop, oldToken);
    }

    /// @notice revoke oldOtoken approval and include new one
    /// @param  start   start index point of the pools array
    /// @param  finish  finish index point of the pools array
    /// @param  _oldOtoken  token to revoke
    /// @dev    this function is manually used in case we have too many pools and gasLimit is reached
    function refreshApprovals(uint256 start, uint256 finish, address _oldOtoken) public nonReentrant {
        VoterAdmin();
        _doRefreshApprovals(start, finish, _oldOtoken);
    }

    function _doRefreshApprovals(uint256 start, uint256 finish, address _oldOtoken) private {
        for (uint256 x = start; x < finish; x++) {
            _refreshApproval(gauges[pools[x]], _oldOtoken);
        }
    }

    function _refreshApproval(address _gauge, address _oldOtoken) internal {
        if (_oldOtoken != address(0)) {
            IERC20(_oldOtoken).approve(_gauge, 0);
        }
        if (oToken == address(0)) {
            IERC20(base).approve(_gauge, type(uint256).max);
        } else {
            IERC20(base).approve(_gauge, 0);
            IERC20(oToken).approve(_gauge, type(uint256).max);
        }
    }

    /// @notice Set depositor that can deposit locked token on behalf of user token
    function setGaugeDepositor(address _depositor, bool _enabled) external {
        VoterAdmin();
        isGaugeDepositor[_depositor] = _enabled;
        emit SetDepositor(_depositor, _enabled);
    }

    /// @notice Set a new Bribe Factory
    function setBribeFactory(address _bribeFactory) external {
        InfraAdmin();
        if (_bribeFactory.code.length == 0) revert NotContract();
        if (_bribeFactory == address(0)) revert ZeroAddress();
        emit SetBribeFactory(bribefactory, _bribeFactory);
        bribefactory = _bribeFactory;
    }

    /// @notice Set a new PermissionRegistry
    function setPermissionsRegistry(address _permissionRegistry) external {
        InfraAdmin();
        if (_permissionRegistry.code.length == 0) revert NotContract();
        if (_permissionRegistry == address(0)) revert ZeroAddress();
        emit SetPermissionRegistry(permissionRegistry, _permissionRegistry);
        permissionRegistry = _permissionRegistry;
    }

    /// @notice Set a new bribes for a given gauge
    function setNewBribes(address _gauge, address _internal, address _external) external {
        VoterAdmin();
        if (!isGauge[_gauge]) revert NotGauge();
        if (_gauge.code.length == 0) revert NotContract();
        _setInternalBribe(_gauge, _internal);
        _setExternalBribe(_gauge, _external);
    }

    /// @notice Set a new internal bribe for a given gauge
    function setInternalBribeFor(address _gauge, address _internal) external {
        VoterAdmin();
        if (!isGauge[_gauge]) revert NotGauge();
        _setInternalBribe(_gauge, _internal);
    }

    /// @notice Set a new External bribe for a given gauge
    function setExternalBribeFor(address _gauge, address _external) external {
        VoterAdmin();
        if (!isGauge[_gauge]) revert NotGauge();
        _setExternalBribe(_gauge, _external);
    }

    function _setInternalBribe(address _gauge, address _internal) private {
        if (_internal.code.length == 0) revert NotContract();
        emit SetBribeFor(true, internal_bribes[_gauge], _internal, _gauge);
        internal_bribes[_gauge] = _internal;
    }

    function _setExternalBribe(address _gauge, address _external) private {
        if (_external.code.length == 0) revert NotContract();
        emit SetBribeFor(false, external_bribes[_gauge], _external, _gauge);
        external_bribes[_gauge] = _external;
    }

    /// @notice Get factory configuration for gauge type
    function getFactoriesForGaugeType(
        uint256 _gaugeType
    ) external view returns (address dexFactory, address gaugeFactory, bool isConfigured) {
        if (!gaugeLogic.isValidGaugeType(_gaugeType) || _gaugeType >= _factories.length) {
            return (address(0), address(0), false);
        }

        dexFactory = _factories[_gaugeType];
        gaugeFactory = _gaugeFactories[_gaugeType];
        isConfigured = (dexFactory != address(0) && gaugeFactory != address(0));
    }

    /// @notice Set factory pair for a specific gauge type
    /// @param _gaugeType The gauge type enum index to configure
    /// @param _pairFactory DEX factory address (address(0) to disable)
    /// @param _gaugeFactory Gauge factory address (address(0) to disable)
    function setFactory(uint256 _gaugeType, address _pairFactory, address _gaugeFactory) external override {
        InfraAdmin();

        // Validation
        if (!gaugeLogic.isValidGaugeType(_gaugeType)) revert InvalidGaugeType();
        if (_pairFactory != address(0) && _pairFactory.code.length == 0) revert NotContract();
        if (_gaugeFactory != address(0) && _gaugeFactory.code.length == 0) revert NotContract();
        if (_pairFactory == address(0) && _gaugeFactory != address(0)) revert InconsistentFactoryPair();
        if (_pairFactory != address(0) && _gaugeFactory == address(0)) revert InconsistentFactoryPair();

        // Expand arrays if needed
        while (_factories.length <= _gaugeType) {
            _factories.push(address(0));
            _gaugeFactories.push(address(0));
        }

        // Get old values for cleanup and events
        address oldPairFactory = _factories[_gaugeType];
        address oldGaugeFactory = _gaugeFactories[_gaugeType];
        bool wasEnabled = (oldPairFactory != address(0) && oldGaugeFactory != address(0));
        bool willBeEnabled = (_pairFactory != address(0) && _gaugeFactory != address(0));

        // Cleanup old factory tracking
        if (oldPairFactory != address(0)) {
            isFactory[oldPairFactory]--;
        }
        if (oldGaugeFactory != address(0)) {
            if (isGaugeFactory[oldGaugeFactory] > 0) {
                isGaugeFactory[oldGaugeFactory]--;
            }
        }

        // Set new factories
        _factories[_gaugeType] = _pairFactory;
        _gaugeFactories[_gaugeType] = _gaugeFactory;

        // Update new factory tracking
        if (_pairFactory != address(0)) {
            /// @dev Enforced that these are updated together
            isFactory[_pairFactory]++;
            isGaugeFactory[_gaugeFactory]++;
        }

        // Emit appropriate events
        if (!wasEnabled && willBeEnabled) {
            emit FactoryEnabled(_gaugeType, _pairFactory, _gaugeFactory);
        } else if (wasEnabled && !willBeEnabled) {
            emit FactoryDisabled(_gaugeType, oldPairFactory, oldGaugeFactory);
        } else if (wasEnabled && willBeEnabled) {
            emit FactoryReplaced(_gaugeType, oldPairFactory, oldGaugeFactory, _pairFactory, _gaugeFactory);
        }
        // Note: if (!wasEnabled && !willBeEnabled) - no event needed for no-op
    }

    /// @notice Set the gauge logic contract
    /// @dev MUST support IVoterV5_GaugeLogic interface
    function setGaugeLogic(address _gaugeLogic) external {
        InfraAdmin();
        _setGaugeLogic(_gaugeLogic);
    }

    function _setGaugeLogic(address _gaugeLogic) private {
        if (!IVoterV5_GaugeLogic(_gaugeLogic).supportsInterface(type(IVoterV5_GaugeLogic).interfaceId)) {
            revert NotGaugeLogic();
        }
        emit SetGaugeLogic(address(gaugeLogic), _gaugeLogic);
        gaugeLogic = IVoterV5_GaugeLogic(_gaugeLogic);
    }

    /// @notice Set the claim logic contract
    /// @dev MUST support IVoterV5_ClaimLogic interface
    function setClaimLogic(address _claimLogic) external {
        InfraAdmin();
        _setClaimLogic(_claimLogic);
    }

    function _setClaimLogic(address _claimLogic) private {
        if (!IVoterV5_ClaimLogic(_claimLogic).supportsInterface(type(IVoterV5_ClaimLogic).interfaceId)) {
            revert NotClaimLogic();
        }
        emit SetClaimLogic(address(claimLogic), _claimLogic);
        claimLogic = IVoterV5_ClaimLogic(_claimLogic);
    }

    function setProtocolName(string memory _protocolName) external {
        VoterAdmin();
        if (bytes(_protocolName).length == 0) {
            revert InvalidProtocolName();
        }
        protocolName = _protocolName;
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    GOVERNANCE
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    //--------------------------------------------------------------------------------
    // Whitelist/Blacklist for Reward Token
    //--------------------------------------------------------------------------------

    /// @notice Whitelist/Blacklist tokens for gauge creation
    function updateWhitelistToken(address[] memory _tokens, bool _whitelist) external {
        VoterOrGaugeAdmin();
        for (uint256 i = 0; i < _tokens.length; i++) {
            _updateWhitelistToken(_tokens[i], _whitelist);
        }
    }

    function _updateWhitelistToken(address _token, bool _whitelist) private {
        if (_token.code.length == 0) revert NotContract();
        isWhitelisted[_token] = _whitelist;
        if (_whitelist) {
            emit Whitelisted(msg.sender, _token);
        } else {
            emit Blacklisted(msg.sender, _token);
        }
    }

    //--------------------------------------------------------------------------------
    // Whitelist/Blacklist for Hypervisor Pools
    //--------------------------------------------------------------------------------

    /// @notice Whitelist/Blacklist pools for gauge creation
    function updateWhitelistPool(address[] memory _pools, bool _whitelist) external {
        VoterOrGaugeAdmin();
        for (uint256 i = 0; i < _pools.length; i++) {
            _updateWhitelistPool(_pools[i], _whitelist);
        }
    }

    function _updateWhitelistPool(address _pool, bool _whitelist) private {
        if (_pool.code.length == 0) revert NotContract();
        isWhitelistedPool[_pool] = _whitelist;
        if (_whitelist) {
            emit WhitelistedPool(msg.sender, _pool);
        } else {
            emit BlacklistedPool(msg.sender, _pool);
        }
    }

    //--------------------------------------------------------------------------------
    // Gauge Kill/Revive
    //--------------------------------------------------------------------------------

    /// @notice Kill a malicious gauge
    /// @param  _gauge gauge to kill
    function killGauge(address _gauge) external {
        IPermissionsRegistry pr = IPermissionsRegistry(permissionRegistry);
        if (!pr.hasRole("GOVERNANCE", msg.sender) && msg.sender != pr.emergencyCouncil()) {
            revert NotAuthorized();
        }
        if (!isAlive[_gauge]) revert GaugeAlreadyKilled();
        // disable allowance
        IERC20(base).approve(_gauge, 0);
        if (oToken != address(0)) {
            IERC20(oToken).approve(_gauge, 0);
        }
        // Return claimable back to minter
        uint256 _claimable = _getRewardSharesForGaugeAndUpdateSupplyIndex(_gauge);
        if (_claimable > 0) {
            IERC20(base).safeTransfer(minter, _claimable); // transfer back to minter to prevent stuck rewards
            emit RefundReward(_gauge, _claimable);
        }
        isAlive[_gauge] = false;
        uint256 _time = _epochTimestamp(); // get start of current epoch
        totalWeightsPerEpoch[_time] -= weightsPerEpoch[_time][poolForGauge[_gauge]];
        weightsPerEpoch[_time][poolForGauge[_gauge]] = 0;
        gaugeKilledEpoch[_gauge] = _time;

        emit GaugeKilled(_gauge);
    }

    /// @notice Revive a malicious gauge
    /// @param  _gauge gauge to revive
    function reviveGauge(address _gauge) external {
        VoterAdmin();
        if (isAlive[_gauge]) revert GaugeAlreadyAlive();
        if (!isGauge[_gauge]) revert NotGauge();
        /// @dev Gauges revived in the same epoch break vote accounting with regards to totalWeightsPerEpoch and _reset()
        if (gaugeKilledEpoch[_gauge] >= _epochTimestamp()) revert CannotReviveGaugeInSameEpoch();
        isAlive[_gauge] = true;
        gaugesDistributionTimestamp[_gauge] = _epochTimestamp();
        supplyIndex[_gauge] = index; // Reset the supply index for backward compatibility
        // reset allowance
        if (oToken != address(0)) {
            IERC20(oToken).approve(_gauge, type(uint256).max);
        } else {
            IERC20(base).approve(_gauge, type(uint256).max);
        }
        emit GaugeRevived(_gauge);
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    USER INTERACTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice Reset the votes of a given TokenID
    function reset() external nonReentrant {
        address _voter = msg.sender;
        _voteDelay(_voter);
        _reset(_voter);
        lastVoted[_voter] = block.timestamp;
    }

    function _reset(address _voter) internal {
        address[] storage _poolVote = poolVote[_voter];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;
        uint256 _time = _epochTimestamp();
        bool votedInEpoch = lastVoted[_voter] >= _time;

        for (uint256 i = 0; i < _poolVoteCnt; i++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_voter][_pool];

            if (_votes != 0) {
                // if user last vote is < than epochTimestamp then votes are 0! IF not underflow occur
                // killGauge resets the weightsPerEpoch, so we don't need to do it here if killed
                /// @dev Killed gauges need to wait until the next epoch to be revived to prevent underflow
                if (votedInEpoch && isAlive[gauges[_pool]]) weightsPerEpoch[_time][_pool] -= _votes;
                votes[_voter][_pool] -= _votes;

                // if is alive remove _votes, else don't because we already done it in killGauge()
                if (isAlive[gauges[_pool]]) _totalWeight += _votes;
                emit Abstained(_voter, _votes);

                IBribe(internal_bribes[gauges[_pool]]).withdraw(uint256(_votes), _voter);
                IBribe(external_bribes[gauges[_pool]]).withdraw(uint256(_votes), _voter);
            }
        }

        // if user last vote is < than epochTimestamp then _totalWeight is 0! IF not underflow occur
        if (lastVoted[_voter] < _time) _totalWeight = 0;
        totalWeightsPerEpoch[_time] -= _totalWeight;
        delete poolVote[_voter];
    }

    /// @notice Recast the saved votes of a given TokenID
    function poke() external nonReentrant {
        address _voter = msg.sender;
        _voteDelay(_voter);
        address[] memory _poolVote = poolVote[_voter];
        uint256 _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);

        for (uint256 i = 0; i < _poolCnt; i++) {
            _weights[i] = votes[_voter][_poolVote[i]];
        }

        _vote(_voter, _poolVote, _weights);
        lastVoted[_voter] = block.timestamp;
    }

    /// @notice Vote for pools
    /// @param  _poolVote   array of LPs addresses to vote  (eg.: [sAMM usdc-usdt   , sAMM busd-usdt, vAMM wbnb-the ,...])
    /// @param  _voteProportions    array of vote proportions for each LPs   (eg.: [10, 90, 45,...])
    function vote(address[] calldata _poolVote, uint256[] calldata _voteProportions) external nonReentrant {
        _voteDelay(msg.sender);
        if (_poolVote.length != _voteProportions.length) revert LengthMismatch();
        _vote(msg.sender, _poolVote, _voteProportions);
        lastVoted[msg.sender] = block.timestamp;
    }

    function _vote(address _voter, address[] memory _poolVote, uint256[] memory _voteProportions) internal {
        _reset(_voter);
        uint256 _poolCnt = _poolVote.length;
        uint256 _time = _epochTimestamp();
        uint256 _weight = IVotingEscrowV2(_ve).getPastVotes(_voter, _time);
        uint256 _totalVoteProportions = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint i = 0; i < _poolCnt; i++) {
            if (isAlive[gauges[_poolVote[i]]]) _totalVoteProportions += _voteProportions[i];
        }

        for (uint256 i = 0; i < _poolCnt; i++) {
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];

            if (isGauge[_gauge] && isAlive[_gauge]) {
                uint256 _poolWeight = (_voteProportions[i] * _weight) / _totalVoteProportions;

                if (votes[_voter][_pool] != 0) revert VotedAlready();
                if (_poolWeight == 0) revert InsufficientVotingPower();

                poolVote[_voter].push(_pool);
                weightsPerEpoch[_time][_pool] += _poolWeight;

                votes[_voter][_pool] += _poolWeight;
                _usedWeight += _poolWeight;
                _totalWeight += _poolWeight;
                emit Voted(msg.sender, _poolWeight);

                IBribe(internal_bribes[_gauge]).deposit(uint256(_poolWeight), _voter);
                IBribe(external_bribes[_gauge]).deposit(uint256(_poolWeight), _voter);
            }
        }

        if (_weight < _totalWeight) revert InsufficientVotingPower();
        totalWeightsPerEpoch[_time] += _totalWeight;
    }

    /// @notice check if user can vote
    /// @param _voter address of the voter to check
    /// @dev Checks if a voter can vote based on:
    /// 1. Vote delay - must wait VOTE_DELAY seconds between votes
    /// 2. Epoch staleness - prevents voting during stale epochs to avoid reset DOS
    function _voteDelay(address _voter) internal view {
        uint256 currentTime = block.timestamp;
        uint256 epochTimestamp = _epochTimestamp();

        /// @dev Prevents double voting on the epoch flip block.
        if (currentTime == epochTimestamp) {
            revert EpochFlipInProgress();
        }

        bool delayMet = currentTime > lastVoted[_voter] + VOTE_DELAY;
        if (!delayMet) {
            revert VoteDelayNotMet();
        }

        /// @dev Prevent voting if the epoch has not yet been flipped
        ///  This protects against `reset` DOS if a user votes during a stale period.
        ///  Once the user tries to vote during the active epoch, `reset` would fail.
        bool epochStale = currentTime > epochTimestamp + DURATION;
        if (epochStale) {
            revert EpochStale();
        }
    }

    /* -----------------------------------------------------------------------------
                                    USER CLAIM GAUGE HELPERS
    ----------------------------------------------------------------------------- */

    /// @notice claim LP gauge rewards
    function claimRewards(address[] memory _gauges) external override {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(IVoterV5_ClaimLogic.claimRewards.selector, _gauges)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim LP gauge rewards for a given address
    function claimRewardsFor(address[] memory _gauges, address _claimFor) external override {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(IVoterV5_ClaimLogic.claimRewardsFor.selector, _gauges, _claimFor)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    function claimRewardTokens(address[] memory _gauges, address[][] memory _tokens) external override {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(IVoterV5_ClaimLogic.claimRewardTokens.selector, _gauges, _tokens)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    function claimRewardTokensFor(
        address[] memory _gauges,
        address[][] memory _tokens,
        address _claimFor
    ) external override {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(IVoterV5_ClaimLogic.claimRewardTokensFor.selector, _gauges, _tokens, _claimFor)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim specific reward tokens for a given address and send them to the caller
    function claimRewardTokensToRecipient(
        address[] memory _gauges,
        address[][] memory _tokens,
        address _claimFor,
        address _recipient
    ) external {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(
                IVoterV5_ClaimLogic.claimRewardTokensToRecipient.selector,
                _gauges,
                _tokens,
                _claimFor,
                _recipient
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim bribes rewards given a TokenID
    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external override {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(
                bytes4(keccak256("claimBribes(address[],address[][],uint256)")),
                _bribes,
                _tokens,
                _tokenId
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim fees rewards given a TokenID
    function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId) external override {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(
                bytes4(keccak256("claimFees(address[],address[][],uint256)")),
                _fees,
                _tokens,
                _tokenId
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim bribes rewards given an address
    function claimBribes(address[] memory _bribes, address[][] memory _tokens) external override {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(bytes4(keccak256("claimBribes(address[],address[][])")), _bribes, _tokens)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim fees rewards given an address
    function claimFees(address[] memory _fees, address[][] memory _tokens) external override {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(bytes4(keccak256("claimFees(address[],address[][])")), _fees, _tokens)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim bribes rewards given a TokenID and send to recipient
    function claimBribesToRecipientByTokenId(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint256 _tokenId,
        address _recipient
    ) external {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(
                IVoterV5_ClaimLogic.claimBribesToRecipientByTokenId.selector,
                _bribes,
                _tokens,
                _tokenId,
                _recipient
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim bribes rewards given an address and send to recipient
    function claimBribesToRecipientByAddress(
        address[] memory _bribes,
        address[][] memory _tokens,
        address _claimFor,
        address _recipient
    ) external {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(
                IVoterV5_ClaimLogic.claimBribesToRecipientByAddress.selector,
                _bribes,
                _tokens,
                _claimFor,
                _recipient
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim fees rewards given a TokenID and send to recipient
    function claimFeesToRecipientByTokenId(
        address[] memory _fees,
        address[][] memory _tokens,
        uint256 _tokenId,
        address _recipient
    ) external {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(
                IVoterV5_ClaimLogic.claimFeesToRecipientByTokenId.selector,
                _fees,
                _tokens,
                _tokenId,
                _recipient
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice claim fees rewards given an address and send to recipient
    function claimFeesToRecipientByAddress(
        address[] memory _fees,
        address[][] memory _tokens,
        address _claimFor,
        address _recipient
    ) external {
        (bool success, bytes memory result) = address(claimLogic).delegatecall(
            abi.encodeWithSelector(
                IVoterV5_ClaimLogic.claimFeesToRecipientByAddress.selector,
                _fees,
                _tokens,
                _claimFor,
                _recipient
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    GAUGE CREATION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */
    /// @notice create multiple gauges
    function createGauges(
        address[] memory _pool,
        uint256[] memory _gaugeTypes
    ) external nonReentrant returns (address[] memory, address[] memory, address[] memory) {
        if (_pool.length != _gaugeTypes.length) revert LengthMismatch();
        if (_pool.length > 10) revert ExceedsMaxGauges();
        address[] memory _gauge = new address[](_pool.length);
        address[] memory _int = new address[](_pool.length);
        address[] memory _ext = new address[](_pool.length);

        uint256 i = 0;
        for (i; i < _pool.length; i++) {
            (_gauge[i], _int[i], _ext[i]) = _createGauge(_pool[i], _gaugeTypes[i]);
        }
        return (_gauge, _int, _ext);
    }

    /// @notice create a gauge
    function createGauge(
        address _pool,
        uint256 _gaugeType
    ) external nonReentrant returns (address _gauge, address _internal_bribe, address _external_bribe) {
        (_gauge, _internal_bribe, _external_bribe) = _createGauge(_pool, _gaugeType);
    }

    /// @notice create a gauge
    /// @param  _pool       LP address
    /// @param  _gaugeType  the type of the gauge you want to create
    /// @dev Logic offloaded to VoterV5_GaugeLogic contract to bring contract size into 24kb range.
    ///   See gaugeLogic contract for more details.
    function _createGauge(
        address _pool,
        uint256 _gaugeType
    ) internal returns (address _gauge, address _internal_bribe, address _external_bribe) {
        (bool success, bytes memory initialResult) = address(gaugeLogic).delegatecall(
            abi.encodeWithSelector(IVoterV5_GaugeLogic.createGauge.selector, _pool, _gaugeType)
        );
        bytes memory result = DelegateCallLib.handleDelegateCallResult(success, initialResult);

        // Decode the result
        (_gauge, _internal_bribe, _external_bribe) = abi.decode(result, (address, address, address));

        emit GaugeCreated(_gauge, msg.sender, _internal_bribe, _external_bribe, _pool);
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    VIEW FUNCTIONS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice view the total length of the pools
    function length() external view returns (uint256) {
        return pools.length;
    }

    /// @notice view the total length of the voted pools given a tokenId
    function poolVoteLength(address voter) external view returns (uint256) {
        return poolVote[voter].length;
    }

    function factories() external view returns (address[] memory) {
        return _factories;
    }

    function factoryLength() external view returns (uint256) {
        return _factories.length;
    }

    function gaugeFactories() external view returns (address[] memory) {
        return _gaugeFactories;
    }

    function gaugeFactoriesLength() external view returns (uint256) {
        return _gaugeFactories.length;
    }

    function weights(address _pool) public view returns (uint256) {
        uint256 _time = _epochTimestamp();
        return weightsPerEpoch[_time][_pool];
    }

    function weightsAt(address _pool, uint256 _time) public view returns (uint256) {
        return weightsPerEpoch[_time][_pool];
    }

    function totalWeight() public view returns (uint256) {
        uint256 _time = _epochTimestamp();
        return totalWeightsPerEpoch[_time];
    }

    function totalWeightAt(uint256 _time) public view returns (uint256) {
        return totalWeightsPerEpoch[_time];
    }

    /// @notice Returns the start time of the current epoch
    function _epochTimestamp() public view returns (uint256) {
        return IMinter(minter).active_period();
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    DISTRIBUTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice notify reward amount for gauge
    /// @dev    Called by the minter once after an epoch flip.
    ///   - DOES NOT support fee on transfer tokens
    /// @param  amount  amount to distribute
    function notifyRewardAmount(uint256 amount) external {
        if (msg.sender != minter) revert NotAuthorized();
        uint256 _previousEpoch = _epochTimestamp() - DURATION;
        uint256 _totalWeight = totalWeightAt(_previousEpoch); // minter call notify after updates active_period, loads votes - 1 week

        uint256 _ratio = 0;

        if (_totalWeight > 0) _ratio = (amount * 1e18) / _totalWeight; // 1e18 adjustment is removed during claim
        if (_ratio > 0) {
            index += _ratio;
        }

        emit NotifyReward(msg.sender, base, amount);
        // @dev Skip transfer when no votes last epoch — minter retains tokens for the next active epoch.
        //      Transferring with _ratio == 0 would lock tokens permanently (index never advances to distribute them).
        if (_ratio == 0) return;
        IERC20(base).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice distribute the LP Fees to the internal bribes
    /// @param  _gauges  gauge address where to claim the fees
    /// @dev    the gauge is the owner of the LPs so it has to claim
    function distributeFees(address[] memory _gauges) external {
        for (uint256 i = 0; i < _gauges.length; i++) {
            if (isGauge[_gauges[i]] && isAlive[_gauges[i]]) {
                IGauge(_gauges[i]).claimFees();
            }
        }
    }

    /// @notice Distribute the emission for ALL gauges
    /// @dev Generally called once after EPOCH flip
    function distributeAll() external nonReentrant {
        IMinter(minter).update_period();

        uint256 x = 0;
        uint256 stop = pools.length;
        for (x; x < stop; x++) {
            _distribute(gauges[pools[x]]);
        }
    }

    /// @notice distribute the emission for N gauges
    /// @param  start   start index point of the pools array
    /// @param  finish  finish index point of the pools array
    /// @dev    this function is used in case we have too many pools and gasLimit is reached
    /// - Generally called once after EPOCH flip
    function distribute(uint256 start, uint256 finish) public nonReentrant {
        IMinter(minter).update_period();
        for (uint256 x = start; x < finish; x++) {
            _distribute(gauges[pools[x]]);
        }
    }

    /// @notice distribute reward only for given gauges
    /// @dev    this function is used in case some distribution fails
    /// - Generally called once after EPOCH flip
    function distribute(address[] memory _gauges) external nonReentrant {
        IMinter(minter).update_period();
        for (uint256 x = 0; x < _gauges.length; x++) {
            _distribute(_gauges[x]);
        }
    }

    /// @notice distribute available emissions for a given gauge
    function _distribute(address _gauge) internal {
        uint256 _claimable = _getRewardSharesForGaugeAndUpdateSupplyIndex(_gauge); // claimable is zero if already updated or killed

        // distribute only if claimable is > 0 and gauge is alive
        if (_claimable > 0) {
            if (isAlive[_gauge]) {
                /// @dev approvals set to MAX_UINT256 in _createGauge()
                if (oToken != address(0)) {
                    IOptionTokenV4(oToken).mint(address(this), _claimable);
                    IGauge(_gauge).notifyRewardAmount(oToken, _claimable);
                } else {
                    IGauge(_gauge).notifyRewardAmount(base, _claimable);
                }
                emit DistributeReward(msg.sender, _gauge, _claimable);
            } else {
                IERC20(base).safeTransfer(minter, _claimable);
                emit RefundReward(_gauge, _claimable);
            }
        }
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    HELPERS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice Update Gauge reward index per vote weight and return accumulated rewards
    function _getRewardSharesForGaugeAndUpdateSupplyIndex(
        address _gauge
    ) private returns (uint256 rewardSharesForGauge) {
        uint256 _gaugeRewardSupplyIndex = supplyIndex[_gauge];
        uint256 _globalRewardIndex = index;
        supplyIndex[_gauge] = _globalRewardIndex; // update _gauge current position to global position

        uint256 _previousEpoch = _epochTimestamp() - DURATION;
        uint256 _previousEpochPoolWeight = weightsPerEpoch[_previousEpoch][poolForGauge[_gauge]];

        if (_previousEpochPoolWeight > 0) {
            uint256 _delta = _globalRewardIndex - _gaugeRewardSupplyIndex; // see if there is any difference that need to be accrued
            if (_delta > 0) {
                rewardSharesForGauge = (_previousEpochPoolWeight * _delta) / 1e18; // add accrued difference for each supplied token
            }
        }
    }

    function ve() external view returns (address) {
        return _ve;
    }
}
