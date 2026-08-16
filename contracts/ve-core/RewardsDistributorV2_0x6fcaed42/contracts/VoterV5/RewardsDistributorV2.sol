// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "../libraries/Math.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IRewardsDistributor.sol";
import "../interfaces/IVersionable.sol";
import {IVotingEscrowV2} from "./VotingEscrow/IVotingEscrowV2.sol";
import {IVotingEscrowV2_Data} from "./VotingEscrow/IVotingEscrowV2_Data.sol";
import {Checkpoints} from "./VotingEscrow/libraries/Checkpoints.sol";
import "../Constants.sol";

/**
 * @title RewardsDistributor for ve(3,3) emissions
 * @author RewardsDistributor V2 ApeGuru
 * @author RewardsDistributor V1 Curve Finance, andrecronje
 * @notice Distributes weekly rebase emissions to VotingEscrow NFTs based on their historical balances.
 * @dev WARN: If a user burns an expired VotingEscrow NFT before claiming rewards, they will lose the unclaimed rewards.
 */
contract RewardsDistributorV2 is IRewardsDistributor, IVersionable {
    /// @notice Emitted when new tokens are accounted for distribution
    event CheckpointToken(uint time, uint tokens);
    /// @notice Emitted when rewards are claimed for a token
    event Claimed(uint tokenId, uint amount, uint claim_epoch, uint max_epoch);
    /// @notice Emitted when a new permanent lock is created upon rebase
    event NewPermanentLockCreated(address indexed tokenOwner, uint indexed newTokenId, uint amount);

    /// @notice Contract semantic version
    string public constant override VERSION = "2.2.0";

    /// @notice Distribution epoch length (seconds)
    uint immutable WEEK = Constants.EPOCH;

    /// @notice Week-aligned start time for distributions
    uint public start_time;
    /// @notice Global time cursor used to pace supply checkpoints
    uint public time_cursor;
    /// @notice Per-token week cursor indicating the next week to claim from
    mapping(uint => uint) public time_cursor_of;

    /// @notice Timestamp when tokens were last checkpointed
    uint public last_token_time;
    /// @notice Mapping of week => amount of tokens to distribute for that week
    uint[1000000000000000] public tokens_per_week;
    /// @notice Cached token balance after last checkpoint to compute deltas
    uint public token_last_balance;

    /// @notice Contract owner
    address public owner;
    /// @notice VotingEscrow contract address
    address public immutable voting_escrow;
    /// @notice Reward token address
    address public immutable token;
    /// @notice Authorized address allowed to checkpoint incoming tokens
    address public depositor;

    /**
     * @notice Deploys the distributor for a specific VotingEscrow instance
     * @param _voting_escrow The address of the VotingEscrow contract
     */
    constructor(address _voting_escrow) {
        uint _t = (block.timestamp / WEEK) * WEEK;
        start_time = _t;
        last_token_time = _t;
        time_cursor = _t;
        address _token = address(IVotingEscrowV2(_voting_escrow).token());
        token = _token;
        voting_escrow = _voting_escrow;
        depositor = msg.sender;
        owner = msg.sender;
        require(IERC20(_token).approve(_voting_escrow, type(uint).max));
    }

    /**
     * @notice Returns the current week-aligned timestamp
     */
    function timestamp() public view returns (uint) {
        return (block.timestamp / WEEK) * WEEK;
    }

    /**
     * @notice Internal: account newly received tokens and allocate across weeks
     * @dev Loop is capped at 20 week-slices to bound gas; sufficient under expected weekly cadence.
     */
    function _checkpoint_token() internal {
        uint token_balance = IERC20(token).balanceOf(address(this));
        uint to_distribute = token_balance - token_last_balance;
        token_last_balance = token_balance;

        uint t = last_token_time;
        uint since_last = block.timestamp - t;
        last_token_time = block.timestamp;
        uint this_week = (t / WEEK) * WEEK;
        uint next_week = 0;

        for (uint i = 0; i < 20; i++) {
            next_week = this_week + WEEK;
            if (block.timestamp < next_week) {
                if (since_last == 0 && block.timestamp == t) {
                    tokens_per_week[this_week] += to_distribute;
                } else {
                    tokens_per_week[this_week] += (to_distribute * (block.timestamp - t)) / since_last;
                }
                break;
            } else {
                if (since_last == 0 && next_week == t) {
                    tokens_per_week[this_week] += to_distribute;
                } else {
                    tokens_per_week[this_week] += (to_distribute * (next_week - t)) / since_last;
                }
            }
            t = next_week;
            this_week = next_week;
        }
        emit CheckpointToken(block.timestamp, to_distribute);
    }

    /**
     * @notice Checkpoints incoming tokens for distribution across weeks
     * @dev Only the `depositor` may call this. Uses current contract balance delta since last checkpoint.
     */
    function checkpoint_token() external {
        assert(msg.sender == depositor);
        _checkpoint_token();
    }

    /**
     * @notice Internal: checkpoint VotingEscrow total supply and roll the time cursor
     */
    function _checkpoint_total_supply() internal {
        IVotingEscrowV2(voting_escrow).checkpoint();
        if (block.timestamp >= time_cursor) time_cursor = timestamp() + WEEK;
    }

    /**
     * @notice Checkpoints the VotingEscrow total supply and advances the distributor time cursor
     */
    function checkpoint_total_supply() external {
        _checkpoint_total_supply();
    }

    /**
     * @notice Internal: compute and record claimable rewards for a token up to a cutoff week
     * @dev Loop is capped at 50 weeks to bound gas. If past total supply is zero for a week where
     *      the token has positive balance, division would revert; the VE invariant should prevent this.
     * @param _tokenId Token ID to claim for
     * @param ve VotingEscrow contract address
     * @param _last_token_time Week-aligned cutoff timestamp
     * @return to_distribute Amount of rewards accrued for the token
     */
    function _claim(uint _tokenId, address ve, uint _last_token_time) internal returns (uint) {
        uint to_distribute = 0;

        (, uint48 maxTs) = IVotingEscrowV2(ve).getPastEscrowPoint(_tokenId, block.timestamp);
        uint _start_time = start_time;

        if (maxTs == 0) return 0;

        uint week_cursor = time_cursor_of[_tokenId];

        if (week_cursor == 0) {
            (, uint48 ts) = IVotingEscrowV2(ve).getFirstEscrowPoint(_tokenId);
            week_cursor = ((ts + WEEK - 1) / WEEK) * WEEK;
        }
        if (week_cursor >= last_token_time) return 0;
        if (week_cursor < _start_time) week_cursor = _start_time;

        for (uint i = 0; i < 50; i++) {
            if (week_cursor >= _last_token_time) break;

            uint256 balance_of = IVotingEscrowV2(ve).balanceOfNFTAt(_tokenId, week_cursor);
            if (balance_of == 0) continue;
            if (balance_of != 0) {
                to_distribute +=
                    (balance_of * tokens_per_week[week_cursor]) /
                    IVotingEscrowV2(ve).getPastTotalSupply(week_cursor);
            }
            week_cursor += WEEK;
        }

        time_cursor_of[_tokenId] = week_cursor;

        emit Claimed(_tokenId, to_distribute, week_cursor, maxTs);

        return to_distribute;
    }

    /**
     * @notice Internal view: simulate rewards claim for a token up to a cutoff week
     * @dev Loop is capped at 50 weeks to bound gas in view context as well.
     * @param _tokenId Token ID to simulate for
     * @param ve VotingEscrow contract address
     * @param _last_token_time Week-aligned cutoff timestamp
     * @return to_distribute Simulated amount of rewards
     */
    function _claimable(uint _tokenId, address ve, uint _last_token_time) internal view returns (uint) {
        uint to_distribute = 0;

        uint _start_time = start_time;

        uint week_cursor = time_cursor_of[_tokenId];

        if (week_cursor == 0) {
            (, uint48 ts) = IVotingEscrowV2(ve).getFirstEscrowPoint(_tokenId);
            if (ts == 0) return 0;
            week_cursor = ((ts + WEEK - 1) / WEEK) * WEEK;
        }

        if (week_cursor >= last_token_time) return 0;
        if (week_cursor < _start_time) week_cursor = _start_time;

        for (uint i = 0; i < 50; i++) {
            if (week_cursor >= _last_token_time) break;
            uint256 balance_of = IVotingEscrowV2(ve).balanceOfNFTAt(_tokenId, week_cursor);
            if (balance_of == 0) break;
            if (balance_of != 0) {
                to_distribute +=
                    (balance_of * tokens_per_week[week_cursor]) /
                    uint256(int256(IVotingEscrowV2(ve).getPastTotalSupply(week_cursor)));
            }
            week_cursor += WEEK;
        }

        return to_distribute;
    }

    /**
     * @notice Returns currently claimable rewards for a token ID
     * @param _tokenId The token ID to check
     * @return The amount of claimable rewards
     */
    function claimable(uint _tokenId) external view returns (uint) {
        uint _last_token_time = (last_token_time / WEEK) * WEEK;
        return _claimable(_tokenId, voting_escrow, _last_token_time);
    }

    /**
     * @notice Get the claimable rewards for a token at a specific timestamp
     * @param _tokenId The token ID to check
     * @param _timestamp The timestamp to query rewards at
     * @return The claimable reward amount at the specified timestamp
     */
    function claimableAt(uint _tokenId, uint _timestamp) external view returns (uint) {
        uint _last_token_time = (_timestamp / WEEK) * WEEK;
        return _claimable(_tokenId, voting_escrow, _last_token_time);
    }

    /**
     * @dev Claims rewards for a token and deposits them into a specified receiver token
     * @param _tokenId The token ID to claim rewards for
     * @param _receiverTokenId The token ID to receive the claimed rewards (must be permanent lock)
     * @return amount The amount of rewards claimed and deposited
     */
    function claimInto(uint _tokenId, uint _receiverTokenId) external returns (uint) {
        // Validate token ownership
        address tokenOwner = IVotingEscrowV2(voting_escrow).ownerOf(_tokenId);
        address receiverOwner = IVotingEscrowV2(voting_escrow).ownerOf(_receiverTokenId);
        require(tokenOwner == receiverOwner, "Token owners must match");

        // Validate receiver is permanent lock
        IVotingEscrowV2.LockDetails memory receiverLock = IVotingEscrowV2(voting_escrow).lockDetails(_receiverTokenId);
        require(receiverLock.lockType == IVotingEscrowV2_Data.LockType.PERMANENT, "Receiver must be permanent lock");

        // Checkpoint if needed
        if (block.timestamp >= time_cursor) _checkpoint_total_supply();
        uint _last_token_time = last_token_time;
        _last_token_time = (_last_token_time / WEEK) * WEEK;
        uint amount = _claim(_tokenId, voting_escrow, _last_token_time);
        _distributeRewards(_tokenId, _receiverTokenId, amount);
        token_last_balance -= amount;
        return amount;
    }

    /**
     * @dev Claims rewards for multiple tokens and deposits them into a specified receiver token
     * @param _tokenIds Array of token IDs to claim rewards for
     * @param _receiverTokenId The token ID to receive the claimed rewards (must be permanent lock)
     * @return success True if the operation completed successfully
     */
    function claimManyInto(uint[] memory _tokenIds, uint _receiverTokenId) external returns (bool) {
        // Validate receiver is permanent lock
        IVotingEscrowV2.LockDetails memory receiverLock = IVotingEscrowV2(voting_escrow).lockDetails(_receiverTokenId);
        require(receiverLock.lockType == IVotingEscrowV2_Data.LockType.PERMANENT, "Receiver must be permanent lock");
        
        address receiverOwner = IVotingEscrowV2(voting_escrow).ownerOf(_receiverTokenId);

        if (block.timestamp >= time_cursor) _checkpoint_total_supply();
        uint _last_token_time = last_token_time;
        _last_token_time = (_last_token_time / WEEK) * WEEK;
        uint total = 0;

        for (uint i = 0; i < _tokenIds.length; i++) {
            uint _tokenId = _tokenIds[i];
            if (_tokenId == 0) break;
            
            address tokenOwner = IVotingEscrowV2(voting_escrow).ownerOf(_tokenId);
            require(tokenOwner == receiverOwner, "Token owners must match");
            
            uint amount = _claim(_tokenId, voting_escrow, _last_token_time);
            _distributeRewards(_tokenId, _receiverTokenId, amount);
            total += amount;
        }
        if (total != 0) {
            token_last_balance -= total;
        }

        return true;
    }

    /**
     * @notice Claims rewards for a token and deposits into the same token
     * @param _tokenId The token ID to claim for
     * @return amount The amount of rewards claimed and deposited
     */
    function claim(uint _tokenId) external returns (uint) {
        if (block.timestamp >= time_cursor) _checkpoint_total_supply();
        uint _last_token_time = last_token_time;
        _last_token_time = (_last_token_time / WEEK) * WEEK;
        uint amount = _claim(_tokenId, voting_escrow, _last_token_time);
        _distributeRewards(_tokenId, _tokenId, amount);
        token_last_balance -= amount;
        return amount;
    }

    /**
     * @notice Claims rewards for multiple tokens, depositing into each corresponding token
     * @param _tokenIds Array of token IDs to claim for
     * @return success True if the operation completed
     */
    function claim_many(uint[] memory _tokenIds) external returns (bool) {
        if (block.timestamp >= time_cursor) _checkpoint_total_supply();
        uint _last_token_time = last_token_time;
        _last_token_time = (_last_token_time / WEEK) * WEEK;
        uint total = 0;

        for (uint i = 0; i < _tokenIds.length; i++) {
            uint _tokenId = _tokenIds[i];
            if (_tokenId == 0) break;
            uint amount = _claim(_tokenId, voting_escrow, _last_token_time);
            _distributeRewards(_tokenId, _tokenId, amount);
            total += amount;
        }
        if (total != 0) {
            token_last_balance -= total;
        }

        return true;
    }

    /**
     * @notice Internal function to handle reward distribution with automatic lock type handling
     * @dev For permanent locks: adds to existing lock. For non-permanent: creates new permanent lock.
     * @param _tokenId The original token ID (used for ownership and event tracking)
     * @param _targetTokenId The target token ID to receive rewards
     * @param _amount The amount of rewards to distribute (must be > 0)
     * @return finalTokenId The token ID that ultimately received the rewards
     */
    function _distributeRewards(uint _tokenId, uint _targetTokenId, uint _amount) internal returns (uint) {
        if (_amount == 0) return _targetTokenId;

        IVotingEscrowV2 ve = IVotingEscrowV2(voting_escrow);
        IVotingEscrowV2.LockDetails memory targetLockDetails = ve.lockDetails(_targetTokenId);

        // Handle permanent locks - increase existing amount
        if (targetLockDetails.lockType == IVotingEscrowV2_Data.LockType.PERMANENT) {
            ve.increaseAmount(_targetTokenId, _amount);
            return _targetTokenId;
        }

        // Handle non-permanent locks - create new permanent lock
        address tokenOwner = ve.ownerOf(_tokenId);
        uint newTokenId = ve.createLockFor(_amount, 0, tokenOwner, IVotingEscrowV2_Data.LockType.PERMANENT);

        emit NewPermanentLockCreated(tokenOwner, newTokenId, _amount);
        return newTokenId;
    }

    /**
     * @notice Sets the address allowed to checkpoint incoming tokens
     * @param _depositor The new depositor address
     */
    function setDepositor(address _depositor) external {
        require(msg.sender == owner);
        depositor = _depositor;
    }

    /**
     * @notice Transfers contract ownership
     * @param _owner The new owner
     */
    function setOwner(address _owner) external {
        require(msg.sender == owner);
        owner = _owner;
    }

    /**
     * @notice Owner-only escape hatch to withdraw arbitrary ERC20 tokens
     * @dev This can withdraw the reward token as well; use with care.
     * @param _token The ERC20 token address to withdraw
     */
    function withdrawERC20(address _token) external {
        require(msg.sender == owner);
        require(_token != address(0));
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, _balance);
    }
}
