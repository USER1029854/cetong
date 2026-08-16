// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPair } from './interfaces/IPair.sol';
import { IBribe } from './interfaces/IBribe.sol';
import { IGauge } from './interfaces/IGauge.sol';
import {IRewarder} from './interfaces/IRewarder.sol';
import {IVersionable} from './interfaces/IVersionable.sol';
import { Math } from "./libraries/Math.sol";
import { Constants } from "./Constants.sol";
import { IVoterV5 } from './VoterV5/IVoterV5.sol';
import {IGaugeV2, IERC165} from './interfaces/IGaugeV2.sol';
import {IMultiTokenPool} from './interfaces/IMultiTokenPool.sol';
import {IGaugeFactoryV2_Base} from './factories/interfaces/IGaugeFactoryV2.sol';
import {CentralTokenPoolModule} from './modules/CentralTokenPoolModule.sol';

/**
 * @title GaugeV2
 * @dev
 *   - 2.1.0: Add depositTo function, Add rewardToken to Harvest event
 *   - 2.2.0: Pull internal_bribe and external_bribe from VoterV5
 *   - 2.3.0: BREAKING Change to IVoterV5.oToken() in updateRewardToken, VoterV5 must support oToken()
 *   - 2.4.0: Add MultiTokenPool integration with secure pool revocation
 */
contract GaugeV2 is CentralTokenPoolModule, ReentrancyGuardUpgradeable, Ownable2StepUpgradeable, IGaugeV2, IVersionable {
    using SafeERC20 for IERC20;

    string public constant override VERSION = "2.4.0";

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    bool public isForPair;
    bool public emergency;

    IERC20 public rewardToken;
    IERC20 public stakeToken;

    address public VE;
    address public DISTRIBUTION;
    address public gaugeRewarder;

    uint256 public DURATION;
    uint internal constant MAX_REWARD_TOKENS = 6;

    address[] public rewards;
    mapping(address => bool) public isReward;

    mapping(address => uint) public rewardRate;
    mapping(address => uint) public periodFinishToken;
    mapping(address => uint) public lastUpdateTime;
    mapping(address => uint) public rewardPerTokenStored;

    mapping(address => mapping(address => uint)) public lastEarn;
    mapping(address => mapping(address => uint)) public userRewardPerTokenStored;
    mapping(address => mapping(address => uint)) public userRewardPerTokenPaid;

    uint256 internal _totalSupply;
    mapping(address => uint256) internal _balances;

    mapping(address => uint) public balanceWithLock;
    mapping(address => uint) public lockEnd;

    /// @dev Central token pool address for cross-chain claims
    address public centralTokenPool;

    /// @dev Gap to provide storage for future variables
    uint256[49] private __gap;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event RewardAdded(uint256 reward);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 reward, address indexed rewardToken);
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
    event EmergencyActivated(address indexed gauge, uint256 timestamp);
    event EmergencyDeactivated(address indexed gauge, uint256 timestamp);
    event SetDistribution(address newDistribution);
    event SetRewarder(address newRewarder);
    event NotifyReward(address sender, address token, uint256 amount);
    event SweepWithdrawToken(address indexed to, IERC20 indexed token, uint256 amount);

    /// -----------------------------------------------------------------------
    /// Custom Errors
    /// -----------------------------------------------------------------------

    error OnlyDistributor();
    error IsEmergency(bool emergency);
    error ZeroAddress();
    error SameAddress();
    error OnlyAllowed();
    error InvalidAmount();
    error NoBalances();

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier updateReward(address account) {
        _updateRewardForAllTokens(account);
        _;
    }

    modifier onlyDistribution() {
        if (msg.sender != DISTRIBUTION) revert OnlyDistributor();
        _;
    }

    modifier isNotEmergency() {
        if (emergency == true) revert IsEmergency(emergency);
        _;
    }

    constructor() {}

    function initialize(
        address _rewardToken,
        address _ve,
        address _stakeToken,
        address _distribution,
        bool _isForPair
    ) public initializer { 
        __GaugeV2_init(_rewardToken, _ve, _stakeToken, _distribution, _isForPair);
    }

    function __GaugeV2_init(
        address _rewardToken,
        address _ve,
        address _stakeToken,
        address _distribution,
        bool _isForPair
    ) internal onlyInitializing {
        __Ownable_init();
        __ReentrancyGuard_init();

        rewardToken = IERC20(_rewardToken); // main reward
        VE = _ve; // vested
        stakeToken = IERC20(_stakeToken); // underlying (LP)
        DISTRIBUTION = _distribution; // distribution address (voter)
        DURATION = Constants.EPOCH; // distribution time

        isForPair = _isForPair; // pair boolean, if false no claim_fees

        emergency = false;

        isReward[_rewardToken] = true;
        rewards.push(_rewardToken);

        // Central token pool module initialization
        address factory = msg.sender;
        address _centralTokenPool = address(0);
        /// @dev Contract can be initialized by zero addresses for the implementation.
        if (_stakeToken != address(0) && _isContract(factory)) {
            try IGaugeFactoryV2_Base(factory).centralTokenPool() returns (address pool) {
                _centralTokenPool = pool;
            } catch {}
            _setCentralTokenPool(_centralTokenPool);
        }
    }



    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    ///@notice set distribution address (should be voter)
    function setDistribution(address _distribution) external virtual onlyOwner {
        if (_distribution == address(0)) revert ZeroAddress();
        if (_distribution == DISTRIBUTION) revert SameAddress();
        DISTRIBUTION = _distribution;
        emit SetDistribution(DISTRIBUTION);
    }

    ///@notice set gauge rewarder address
    function setGaugeRewarder(address _gaugeRewarder) external virtual onlyOwner {
        if (_gaugeRewarder == gaugeRewarder) revert SameAddress();
        gaugeRewarder = _gaugeRewarder;
        emit SetRewarder(gaugeRewarder);
    }

    function activateEmergencyMode() external onlyOwner {
        if (emergency == true) revert IsEmergency(emergency);
        emergency = true;
        emit EmergencyActivated(address(this), block.timestamp);
    }

    function stopEmergencyMode() external onlyOwner {
        if (emergency == false) revert IsEmergency(emergency);
        emergency = false;
        emit EmergencyDeactivated(address(this), block.timestamp);
    }

    /// @notice Update rewardToken address to match with Voter contract
    function updateRewardToken() external virtual onlyOwner {
        isReward[address(rewardToken)] = false;
        address rewardAddress = _getVoterOToken();
        if (rewardAddress == address(0)) {
            rewardAddress = IVoterV5(DISTRIBUTION).base();
        }

        if (!isReward[rewardAddress]) {
            isReward[rewardAddress] = true;
            rewards.push(rewardAddress);
        }

        rewardToken = IERC20(rewardAddress);
    }

    /// @notice Owner can add reward tokens beyond limit
    function addRewardToken(address _rewardToken) external virtual onlyOwner {
        if (!isReward[_rewardToken]) {
            isReward[_rewardToken] = true;
            rewards.push(_rewardToken);
        } else {
            revert("Already added");
        }
    }

    function removeRewardToken(address _rewardToken) external virtual onlyOwner {
        require(isReward[_rewardToken], "Not added");
        _updateRewardForAllTokens(address(this));
        for (uint i = 0; i < rewards.length; i++) {
            if (rewards[i] == _rewardToken) {
                rewards[i] = rewards[rewards.length - 1];
                rewards.pop();
                break;
            }
        }
        isReward[_rewardToken] = false;
    }

    /// @notice Owner can sweep tokens in case of emergency
    function sweepTokens(IERC20[] memory tokens, uint256[] memory amounts, address to) public onlyOwner {
        require(tokens.length == amounts.length, "Tokens and amounts length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            require(token != stakeToken, "Cannot sweep stake token");
            uint256 amount = amounts[i];
            uint256 balance = token.balanceOf(address(this));
            require(balance >= amount, "Insufficient token balance");
            token.transfer(to, amount);
            emit SweepWithdrawToken(to, token, amount);
        }
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    VIEW FUNCTIONS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    ///@notice total supply held
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    ///@notice balance of a user
    function balanceOf(address account) external view virtual returns (uint256) {
        return _balances[account];
    }

    function availableBalance(address account) public view virtual returns (uint) {
        if (block.timestamp >= lockEnd[account]) return _balances[account];
        return _balances[account] - balanceWithLock[account];
    }

    function lastTimeRewardApplicable(address rewardAddress) public view virtual returns (uint256) {
        return Math.min(block.timestamp, periodFinishToken[rewardAddress]);
    }

    function rewardPerToken(address rewardAddress) public view virtual returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored[rewardAddress];
        } else {
            return
                rewardPerTokenStored[rewardAddress] +
                ((lastTimeRewardApplicable(rewardAddress) - lastUpdateTime[rewardAddress]) *
                    rewardRate[rewardAddress] *
                    1e18) /
                _totalSupply;
        }
    }

    ///@notice see earned rewards for user
    function earned(address account) external view virtual returns (uint256) {
        return earned(account, address(rewardToken));
    }

    ///@notice see earned rewards for user
    function earned(address account, address rewardAddress) public view virtual returns (uint256) {
        return
            userRewardPerTokenStored[rewardAddress][account] +
            (_balances[account] * (rewardPerToken(rewardAddress) - userRewardPerTokenPaid[rewardAddress][account])) /
            1e18;
    }

    ///@notice get total reward for the duration
    function rewardForDuration(address rewardAddress) public view virtual returns (uint256) {
        return rewardRate[rewardAddress] * DURATION;
    }

    function periodFinish(address rewardAddress) public view virtual returns (uint256) {
        return periodFinishToken[rewardAddress];
    }

    ///@notice get the internal bribe address for this gauge. LP fees are sent here.
    ///@dev Using snake case for backward compatibility
    function internal_bribe() public view returns (address) {
        return IVoterV5(DISTRIBUTION).internal_bribes(address(this));
    }

    ///@notice get the external bribe address for this gauge. Bribe fees are sent here.
    ///@dev Using snake case for backward compatibility
    function external_bribe() public view returns (address) {
        return IVoterV5(DISTRIBUTION).external_bribes(address(this));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool supported) {
        return interfaceId == type(IGaugeV2).interfaceId;
    }

    function left(address token) external view virtual returns (uint) {
        if (block.timestamp >= periodFinishToken[token]) return 0;
        uint _remaining = periodFinishToken[token] - block.timestamp;
        return _remaining * rewardRate[token];
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    USER INTERACTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    ///@notice deposit all stakeToken of msg.sender
    function depositAll() external virtual {
        _deposit(stakeToken.balanceOf(msg.sender), msg.sender);
    }

    ///@notice deposit amount stakeToken
    function deposit(uint256 amount) external virtual {
        _deposit(amount, msg.sender);
    }

    ///@notice deposit amount stakeToken to account
    function depositTo(uint256 amount, address account) external virtual {
        _deposit(amount, account);
    }

    ///@notice deposits a locked LP position. Generally called from oToken
    function depositWithLock(address account, uint256 amount, uint256 _lockDuration) external virtual {
        require(
            msg.sender == account ||
                msg.sender == address(rewardToken) ||
                IVoterV5(DISTRIBUTION).isGaugeDepositor(msg.sender),
            "Not allowed to deposit with lock"
        );
        _deposit(amount, account);

        if (block.timestamp >= lockEnd[account]) {
            // if the current lock is expired release the tokens from that lock before locking again
            delete lockEnd[account];
            delete balanceWithLock[account];
        }

        balanceWithLock[account] += amount;
        uint256 currentLockEnd = lockEnd[account];
        uint256 newLockEnd = block.timestamp + _lockDuration;
        if (currentLockEnd > newLockEnd) {
            // The lock end can only be extended
            revert("The current lock end > new lock end");
        }
        lockEnd[account] = newLockEnd;
    }

    /// @notice Internal deposit function with all checks and pool integration
    function _deposit(uint256 amount, address account) internal nonReentrant isNotEmergency updateReward(account) {
        if (amount <= 0) revert InvalidAmount();

        _balances[account] = _balances[account] + amount;
        _totalSupply = _totalSupply + amount;

        if (address(gaugeRewarder) != address(0)) {
            IRewarder(gaugeRewarder).onReward(account, account, _balances[account]);
        }

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        // If central pool is enabled, deposit tokens to the pool for cross-chain access
        if (_isCentralTokenPoolEnabled()) {
            _depositToCentralTokenPool(stakeToken, amount);
        }

        emit Deposit(account, amount);
    }

    ///@notice withdraw all token
    function withdrawAll() external virtual {
        _withdraw(_balances[msg.sender]);
    }

    /// @notice Withdraw a specific amount of tokens from the gauge
    function withdraw(uint256 amount) external virtual {
        _withdraw(amount);
    }

    /// @notice Internal withdraw function with all checks and pool integration
    function _withdraw(uint256 amount) internal nonReentrant isNotEmergency updateReward(msg.sender) {
        if (amount <= 0) revert InvalidAmount();
        if (_balances[msg.sender] <= 0) revert NoBalances();

        if (block.timestamp >= lockEnd[msg.sender]) {
            // if the current lock is expired, release the tokens
            delete lockEnd[msg.sender];
            delete balanceWithLock[msg.sender];
        }

        uint256 totalBalance = _balances[msg.sender];
        uint256 lockedAmount = balanceWithLock[msg.sender];
        uint256 freeAmount = totalBalance - lockedAmount;

        // Update lock related mappings when withdraw amount greater than free amount
        if (amount > freeAmount) {
            revert("Cannot withdraw more than free amount");
        }

        _totalSupply -= amount;
        _balances[msg.sender] -= amount;

        if (address(gaugeRewarder) != address(0)) {
            IRewarder(gaugeRewarder).onReward(msg.sender, msg.sender, _balances[msg.sender]);
        }

        _safeTransferStakeToken(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function emergencyWithdraw() external virtual nonReentrant {
        if (!emergency) revert IsEmergency(emergency);
        if (_balances[msg.sender] <= 0) revert NoBalances();

        uint256 _amount = _balances[msg.sender];
        _totalSupply = _totalSupply - _amount;
        _balances[msg.sender] = 0;
        delete lockEnd[msg.sender];
        delete balanceWithLock[msg.sender];

        _updateRewardForAllTokens(address(0));

        if (gaugeRewarder != address(0)) {
            IRewarder(gaugeRewarder).onEmergencyWithdrawAmount(msg.sender, _amount);
        }

        _safeTransferStakeTokenEmergency(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }
    function emergencyWithdrawAmount(uint256 _amount) external virtual nonReentrant {
        if (!emergency) revert IsEmergency(emergency);
        if (_balances[msg.sender] < _amount) revert NoBalances();

        _totalSupply = _totalSupply - _amount;
        _balances[msg.sender] -= _amount;
        delete lockEnd[msg.sender];
        delete balanceWithLock[msg.sender];

        _updateRewardForAllTokens(address(0));

        if (gaugeRewarder != address(0)) {
            IRewarder(gaugeRewarder).onEmergencyWithdrawAmount(msg.sender, _amount);
        }

        _safeTransferStakeTokenEmergency(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    ///@notice withdraw all stakeToken and harvest rewardToken
    function withdrawAllAndHarvest() external virtual {
        _withdraw(_balances[msg.sender]);
        getReward();
    }

    /// @notice User harvest function called from distribution (voter allows harvest on multiple gauges)
    function getReward(address _user) external virtual onlyDistribution {
        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken);
        return _getReward(_user, _user, tokens);
    }

    /// @notice User harvest function
    /// Enables backward compatibility and focuses on harvesting main reward tokern
    function getReward() public virtual {
        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken);
        return _getReward(msg.sender, msg.sender, tokens);
    }

    ///@notice User harvest function called from distribution (voter allows harvest on multiple gauges)
    function getReward(address _user, address[] memory tokens) external virtual {
        require(msg.sender == _user || msg.sender == DISTRIBUTION, "Not authorized");
        return _getReward(_user, _user, tokens);
    }

    /// @notice Claim specific reward tokens for a user and send to recipient
    function getRewardToRecipient(address _user, address _recipient, address[] memory tokens) external virtual {
        require(msg.sender == _user || msg.sender == DISTRIBUTION, "Not authorized");
        _getReward(_user, _recipient, tokens);
    }

    function _getReward(
        address _user,
        address _recipient,
        address[] memory tokens
    ) internal nonReentrant updateReward(_user) {
        uint length = tokens.length;
        for (uint i = 0; i < length; i++) {
            address rewardAddress = tokens[i];
            uint256 reward = userRewardPerTokenStored[rewardAddress][_user];
            if (reward > 0) {
                userRewardPerTokenStored[rewardAddress][_user] = 0;
                IERC20(rewardAddress).safeTransfer(_recipient, reward);
                emit Harvest(_user, reward, rewardAddress);
            }
        }
        if (gaugeRewarder != address(0)) {
            IRewarder(gaugeRewarder).onReward(_user, _recipient, _balances[_user]);
        }
    }

    function _updateRewardForAllTokens(address account) internal {
        uint256 length = rewards.length;
        for (uint i; i < length; i++) {
            address rewardAddress = rewards[i];
            rewardPerTokenStored[rewardAddress] = rewardPerToken(rewardAddress);
            lastUpdateTime[rewardAddress] = lastTimeRewardApplicable(rewardAddress);
            if (account != address(0)) {
                userRewardPerTokenStored[rewardAddress][account] = earned(account, rewardAddress);
                userRewardPerTokenPaid[rewardAddress][account] = rewardPerTokenStored[rewardAddress];
            }
        }
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    DISTRIBUTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @dev Receive rewards
    function notifyRewardAmount(
        address rewardAddress,
        uint256 rewardAmount
    ) external virtual nonReentrant isNotEmergency updateReward(address(0)) {
        uint256 balanceBefore = IERC20(rewardAddress).balanceOf(address(this));
        IERC20(rewardAddress).safeTransferFrom(msg.sender, address(this), rewardAmount);
        uint256 balanceAfter = IERC20(rewardAddress).balanceOf(address(this));
        rewardAmount = balanceAfter - balanceBefore;

        _notifyRewardAmount(rewardAddress, rewardAmount);
    }

    /// @notice helper for updateRewardToken to be able to override
    function _getVoterOToken() internal view virtual returns (address) {
        return IVoterV5(DISTRIBUTION).oToken();
    }

    function _notifyRewardAmount(address rewardAddress, uint rewardAmount) internal {
        require(rewardAddress != address(stakeToken), "Can't add stake token as reward");
        require(rewardAmount > 0, "Reward amount needs to be higher than 0");
        if (!isReward[rewardAddress]) {
            require(IVoterV5(DISTRIBUTION).isWhitelisted(rewardAddress), "rewards tokens must be whitelisted");
            if (rewardAddress != _getVoterOToken() && rewardAddress != IVoterV5(DISTRIBUTION).base())
                require(rewards.length < MAX_REWARD_TOKENS, "too many rewards tokens");
        }
        if (block.timestamp >= periodFinishToken[rewardAddress]) {
            rewardRate[rewardAddress] = rewardAmount / DURATION;
        } else {
            uint256 remaining = periodFinishToken[rewardAddress] - block.timestamp;
            uint256 leftover = remaining * rewardRate[rewardAddress];
            require(rewardAmount > leftover, "Cannot decrease reward rate");
            /// @dev: This will spread the remaining rewards over the new period.
            rewardRate[rewardAddress] = (rewardAmount + leftover) / DURATION;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = IERC20(rewardAddress).balanceOf(address(this));
        require(rewardRate[rewardAddress] <= balance / DURATION, "Provided reward too high");

        lastUpdateTime[rewardAddress] = block.timestamp;
        periodFinishToken[rewardAddress] = block.timestamp + DURATION;
        if (!isReward[rewardAddress]) {
            isReward[rewardAddress] = true;
            rewards.push(rewardAddress);
        }

        emit NotifyReward(msg.sender, rewardAddress, rewardAmount);
    }

    function claimFees() external nonReentrant returns (uint256 claimed0, uint256 claimed1) {
        return _claimFees();
    }

    function _claimFees() internal virtual returns (uint256 claimed0, uint256 claimed1) {
        if (!isForPair) {
            return (0, 0);
        }
        address _token = address(stakeToken);
        (claimed0, claimed1) = IPair(_token).claimFees();
        if (claimed0 > 0 || claimed1 > 0) {
            uint256 _fees0 = claimed0;
            uint256 _fees1 = claimed1;

            (address _token0, address _token1) = IPair(_token).tokens();

            address internalBribe = internal_bribe();

            if (_fees0 > 0) {
                IERC20(_token0).approve(internalBribe, 0);
                IERC20(_token0).approve(internalBribe, _fees0);
                IBribe(internalBribe).notifyRewardAmount(_token0, _fees0);
            }
            if (_fees1 > 0) {
                IERC20(_token1).approve(internalBribe, 0);
                IERC20(_token1).approve(internalBribe, _fees1);
                IBribe(internalBribe).notifyRewardAmount(_token1, _fees1);
            }
            emit ClaimFees(msg.sender, claimed0, claimed1);
        }
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                           MULTITOKENPOOL MODULE IMPLEMENTATION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice transfer stakeToken to account
    /// @dev if central pool is enabled, withdraw tokens from the pool first
    function _safeTransferStakeToken(address account, uint256 amount) internal {
        if (_isCentralTokenPoolEnabled()) {
            _withdrawFromCentralTokenPool(stakeToken, amount);
        }
        stakeToken.safeTransfer(account, amount);
    }

    /// @notice Emergency transfer stakeToken to account bypassing central pool failures
    /// @dev Used in emergency mode - attempts central pool withdrawal but continues if it fails
    function _safeTransferStakeTokenEmergency(address account, uint256 amount) internal {
        if (_isCentralTokenPoolEnabled()) {
            try this._withdrawFromCentralPoolSafe(stakeToken, amount) {
                // Success - tokens withdrawn from central pool
            } catch {
                // Central pool withdrawal failed - continue with direct transfer
                // This ensures users can always withdraw in emergency mode even if pool is broken
            }
        }
        
        // Ensure we have sufficient tokens in the contract
        uint256 contractBalance = stakeToken.balanceOf(address(this));
        require(contractBalance >= amount, "Insufficient tokens for emergency withdrawal");
        
        stakeToken.safeTransfer(account, amount);
    }

    /// @notice Safe wrapper for central pool withdrawal that can be called via try/catch
    /// @dev External function to enable try/catch pattern in _safeTransferStakeTokenEmergency
    function _withdrawFromCentralPoolSafe(IERC20 token, uint256 amount) external {
        require(msg.sender == address(this), "Only self-call allowed");
        _withdrawFromCentralTokenPool(token, amount);
    }

    /// @notice Implementation of virtual access function
    /// @inheritdoc CentralTokenPoolModule
    function getCentralTokenPool() public view override returns (address) {
        return centralTokenPool;
    }

    /// @notice Implementation of virtual setter function
    /// @dev ⚠️  WARNING: This function bypasses all validation checks!
    ///      - DO NOT call this function directly
    ///      - Use _setCentralTokenPool() instead for safe operations
    ///      - Only called internally by the validated _setCentralTokenPool()
    ///      - This is an implementation detail of CentralTokenPoolModule
    /// @param newPool The new pool address (UNCHECKED - can be invalid!)
    function _setCentralTokenPoolUnchecked(address newPool) internal override {
        centralTokenPool = newPool;
    }

    /// @notice Public function that delegates to module
    /// @dev Only callable by gauge owner/admin. This is a one-way operation - pool can only be re-enabled via upgrade
    function revokeCentralTokenPool() external onlyOwner {
        _revokeCentralTokenPool(stakeToken);
    }

    /// @notice Helper function to check if an address contains contract code
    /// @dev Used during initialization to validate factory responses
    function _isContract(address addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}
