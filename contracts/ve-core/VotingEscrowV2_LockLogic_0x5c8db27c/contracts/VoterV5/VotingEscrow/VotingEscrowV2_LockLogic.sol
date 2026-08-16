// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotingEscrowV2_LockLogic} from "./IVotingEscrowV2_LockLogic.sol";
import {IVotingEscrowV2_Storage} from "./IVotingEscrowV2_Storage.sol";
import {VotingEscrowV2_Storage} from "./VotingEscrowV2_Storage.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {EscrowDelegateCheckpoints, Checkpoints} from "./libraries/EscrowDelegateCheckpoints.sol";
import {SafeCastLibrary} from "./libraries/SafeCastLibrary.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC5725Upgradeable} from "./erc5725/IERC5725Upgradeable.sol";
import {ERC5725Upgradeable} from "./erc5725/ERC5725Upgradeable.sol";
import {IVotingEscrowV2_Data} from "./IVotingEscrowV2_Data.sol";

contract VotingEscrowV2_LockLogic is IVotingEscrowV2_LockLogic, VotingEscrowV2_Storage {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeCastLibrary for uint256;
    using EscrowDelegateCheckpoints for EscrowDelegateCheckpoints.EscrowDelegateStore;

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    modifier checkAuthorized(uint256 _tokenId) {
        address owner = ownerOf(_tokenId);
        if (owner == address(0)) {
            revert ERC721NonexistentToken(_tokenId);
        }
        address sender = msg.sender;
        if (!_isAuthorized(owner, sender, _tokenId)) {
            revert ERC721InsufficientApproval(sender, _tokenId);
        }
        _;
    }

    function _createLock(
        uint256 value,
        uint256 duration,
        address to,
        address delegatee,
        LockType lockType,
        DepositType depositType
    ) internal returns (uint256) {
        if (value == 0) revert ZeroAmount();
        uint256 unlockTime;
        totalNftsMinted++;
        uint256 newTokenId = totalNftsMinted; // 1 indexed
        bool permanent = lockType != LockType.NON_PERMANENT;
        if (!permanent) {
            unlockTime = toGlobalClock(block.timestamp + duration); // Locktime is rounded down to global clock (days)
            if (unlockTime <= block.timestamp) revert LockDurationNotInFuture();
            if (unlockTime > block.timestamp + MAX_TIME) revert LockDurationTooLong();
        }
        _mint(to, newTokenId);
        __lockDetails[newTokenId].startTime = block.timestamp;
        _updateLock(newTokenId, value, unlockTime, __lockDetails[newTokenId], lockType, depositType);
        edStore.delegate(newTokenId, delegatee, unlockTime);
        emit LockCreated(newTokenId, delegatee, value, unlockTime, lockType);
        emit DelegateChanged(to, address(0), delegatee);
        emit LockDelegateChanged(newTokenId, to, address(0), delegatee);
        return newTokenId;
    }

    function createLock(uint256 _value, uint256 _lockDuration, LockType _lockType) external override returns (uint256) {
        return _createLock(_value, _lockDuration, msg.sender, msg.sender, _lockType, DepositType.CREATE_LOCK_TYPE);
    }

    function createLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        LockType _lockType
    ) external override returns (uint256) {
        return _createLock(_value, _lockDuration, _to, _to, _lockType, DepositType.CREATE_LOCK_TYPE);
    }

    function createDelegatedLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        address _delegatee,
        LockType _lockType
    ) external override returns (uint256) {
        return _createLock(_value, _lockDuration, _to, _delegatee, _lockType, DepositType.CREATE_LOCK_TYPE);
    }

    function createClaimableLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        address _delegatee,
        LockType _lockType
    ) external override returns (uint256) {
        uint256 tokenId = _createLock(_value, _lockDuration, _to, _delegatee, _lockType, DepositType.CREATE_LOCK_TYPE);
        
        _claimRedirectApprovalsForToken[tokenId] = _delegatee;
        emit ClaimRedirectApproval(_to, _delegatee, tokenId);
        
        return tokenId;
    }

    function _updateLock(
        uint256 _tokenId,
        uint256 _increasedValue,
        uint256 _unlockTime,
        LockDetails memory _oldLocked,
        LockType lockType,
        DepositType depositType
    ) internal {
        uint256 supplyBefore = supply;
        supply += _increasedValue;

        LockDetails memory newLocked;
        (newLocked.amount, newLocked.startTime, newLocked.endTime, newLocked.lockType) = (
            _oldLocked.amount,
            _oldLocked.startTime,
            _oldLocked.endTime,
            _oldLocked.lockType
        );

        if (_unlockTime != 0 && lockType == LockType.NON_PERMANENT) {
            newLocked.endTime = _unlockTime;
        }

        if (lockType != LockType.NON_PERMANENT) {
            newLocked.endTime = 0;
        }

        newLocked.lockType = lockType;

        if (_increasedValue != 0 && depositType != DepositType.SPLIT_TYPE) {
            if (lockType == LockType.PERMANENT) {
                newLocked.amount += (_increasedValue * 1 ether) / 1.3 ether;
                token.burnFrom(msg.sender, _increasedValue);
            } else {
                newLocked.amount += _increasedValue;
                IERC20Upgradeable(address(token)).safeTransferFrom(msg.sender, address(this), _increasedValue);
            }
            emit SupplyUpdated(supplyBefore, supply);
        } else if (_increasedValue != 0) {
            newLocked.amount += _increasedValue;
        }
        __lockDetails[_tokenId] = newLocked;
        emit LockUpdated(_tokenId, _increasedValue, _unlockTime, lockType);

        _checkpointLock(_tokenId, _oldLocked, newLocked);
    }

    function increaseAmount(uint256 _tokenId, uint256 _value) external override {
        if (_value == 0) revert ZeroAmount();

        LockDetails memory oldLocked = __lockDetails[_tokenId];
        if (ownerOf(_tokenId) == address(0)) revert ERC721NonexistentToken(_tokenId);
        if (oldLocked.endTime <= block.timestamp && oldLocked.lockType == LockType.NON_PERMANENT) revert LockExpired();

        _updateLock(_tokenId, _value, 0, oldLocked, oldLocked.lockType, DepositType.INCREASE_LOCK_AMOUNT);
    }

    function increaseUnlockTime(
        uint256 _tokenId,
        uint256 _lockDuration,
        bool _permanent
    ) external override checkAuthorized(_tokenId) {
        LockDetails memory oldLocked = __lockDetails[_tokenId];
        if (oldLocked.lockType == LockType.PERMANENT || oldLocked.lockType == LockType.ROLLING) revert PermanentLock();
        if (oldLocked.endTime <= block.timestamp) revert LockExpired();
        if (oldLocked.amount == 0) revert ZeroAmount();

        uint256 unlockTime;
        LockType lockType = _permanent ? LockType.ROLLING : LockType.NON_PERMANENT;
        if (!_permanent) {
            unlockTime = toGlobalClock(block.timestamp + _lockDuration);
            if (unlockTime <= oldLocked.endTime) revert LockDurationNotInFuture();
            if (unlockTime > block.timestamp + MAX_TIME) revert LockDurationTooLong();
        }

        _updateLock(_tokenId, 0, unlockTime, oldLocked, lockType, DepositType.INCREASE_UNLOCK_TIME);
        emit LockDurationExtended(_tokenId, unlockTime, _permanent);
    }

    function unlockRolling(uint256 _tokenId) external override checkAuthorized(_tokenId) {
        LockDetails memory newLocked = __lockDetails[_tokenId];
        if (newLocked.lockType != LockType.ROLLING) revert NotPermanentLock();

        newLocked.endTime = toGlobalClock(block.timestamp + MAX_TIME);
        newLocked.lockType = LockType.NON_PERMANENT;

        _checkpointLock(_tokenId, __lockDetails[_tokenId], newLocked);
        __lockDetails[_tokenId] = newLocked;

        emit UnlockRolling(_tokenId, msg.sender, newLocked.endTime);
    }

    function _claim(uint256 _tokenId) internal checkAuthorized(_tokenId) {
        LockDetails memory oldLocked = __lockDetails[_tokenId];
        if (oldLocked.lockType != LockType.NON_PERMANENT) revert PermanentLock();

        uint256 amountClaimed;
        uint256 penaltyAmount = 0;

        if (oldLocked.endTime > block.timestamp) {
            uint256 claimableAmount;
            (penaltyAmount, claimableAmount) = _calculateEarlyExitPenalty(_tokenId, oldLocked.amount);
            amountClaimed = claimableAmount;
            if (penaltyAmount > 0) {
                emit EarlyExitPenalty(_tokenId, msg.sender, penaltyAmount, amountClaimed);
                token.burn(penaltyAmount);
            }
        } else {
            amountClaimed = vestedPayout(_tokenId);
            if (amountClaimed == 0) revert LockNotExpired();
        }

        __lockDetails[_tokenId] = LockDetails(0, 0, 0, LockType.NON_PERMANENT);
        uint256 supplyBefore = supply;
        supply -= (amountClaimed + penaltyAmount);

        _checkpointLock(_tokenId, oldLocked, __lockDetails[_tokenId]);

        emit PayoutClaimed(_tokenId, msg.sender, amountClaimed);

        _payoutClaimed[_tokenId] += amountClaimed;
        IERC20Upgradeable(address(token)).safeTransfer(msg.sender, amountClaimed);

        emit SupplyUpdated(supplyBefore, supply);
    }

    function claim(uint256 _tokenId) external override(IVotingEscrowV2_LockLogic, VotingEscrowV2_Storage) {
        _claim(_tokenId);
    }

    function merge(uint256 _from, uint256 _to) external override checkAuthorized(_from) checkAuthorized(_to) {
        if (_from == _to) revert SameNFT();

        LockDetails storage oldLockedTo = __lockDetails[_to];
        if (oldLockedTo.amount == 0) revert ZeroAmount();
        if (oldLockedTo.endTime <= block.timestamp && oldLockedTo.lockType == LockType.NON_PERMANENT)
            revert LockExpired();

        LockDetails storage oldLockedFrom = __lockDetails[_from];
        if (oldLockedFrom.amount == 0) revert ZeroAmount();

        if (
            (oldLockedFrom.lockType == LockType.PERMANENT || oldLockedTo.lockType == LockType.PERMANENT) &&
            (oldLockedFrom.lockType != oldLockedTo.lockType)
        ) {
            revert PermanentLockMismatch();
        }
        if (oldLockedFrom.lockType == LockType.ROLLING && oldLockedTo.lockType != LockType.ROLLING) {
            revert RollingLockMismatch();
        }

        uint256 endTime = oldLockedFrom.endTime >= oldLockedTo.endTime ? oldLockedFrom.endTime : oldLockedTo.endTime;
        uint256 fromAmount = oldLockedFrom.amount;
        uint256 toAmount = oldLockedTo.amount;
        LockType toLockType = oldLockedTo.lockType;

        _zeroAndCheckpointFromLock(_from, oldLockedFrom);
        _updateAndCheckpointToLock(_to, oldLockedTo, fromAmount, endTime);

        emit LockMerged(_from, _to, toAmount + fromAmount, endTime, toLockType);
    }

    function _zeroAndCheckpointFromLock(uint256 _fromTokenId, LockDetails storage _oldLockedFrom) internal {
        LockDetails memory oldLockedFromMemory = _oldLockedFrom;
        _oldLockedFrom.amount = 0;
        _checkpointLock(_fromTokenId, oldLockedFromMemory, _oldLockedFrom);
    }

    function _updateAndCheckpointToLock(
        uint256 _toTokenId,
        LockDetails storage _oldLockedTo,
        uint256 _fromAmount,
        uint256 _endTime
    ) internal {
        LockDetails memory newLockedTo;
        newLockedTo.amount = _oldLockedTo.amount + _fromAmount;
        newLockedTo.startTime = _oldLockedTo.startTime;
        newLockedTo.lockType = _oldLockedTo.lockType;
        if (newLockedTo.lockType != LockType.PERMANENT && newLockedTo.lockType != LockType.ROLLING) {
            newLockedTo.endTime = _endTime;
        }

        _checkpointLock(_toTokenId, _oldLockedTo, newLockedTo);
        __lockDetails[_toTokenId] = newLockedTo;
    }

    function split(uint256[] memory _weights, uint256 _tokenId) external override checkAuthorized(_tokenId) {
        LockDetails memory locked = __lockDetails[_tokenId];
        LockDetails storage lockedStorage = __lockDetails[_tokenId];
        uint256 currentTime = block.timestamp;
        if (locked.endTime <= currentTime && locked.lockType == LockType.NON_PERMANENT) revert LockExpired();
        if (locked.amount == 0 || _weights.length < 2) revert ZeroAmount();

        supply -= locked.amount;
        address owner = ownerOf(_tokenId);
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            totalWeight += _weights[i];
        }
        if (totalWeight == 0) revert InvalidWeights();

        uint256 duration = locked.lockType != LockType.NON_PERMANENT ? 0 : locked.endTime - currentTime;

        uint256 amountLeftToSplit = locked.amount;
        for (uint256 i = 0; i < _weights.length; i++) {
            uint256 value = (uint256(int256(locked.amount)) * _weights[i]) / totalWeight;
            if (i == _weights.length - 1) {
                value = amountLeftToSplit;
            }
            amountLeftToSplit -= value;
            if (i == 0) {
                lockedStorage.amount = value;
                supply += value;
                _checkpointLock(_tokenId, locked, lockedStorage);
            } else {
                _createLock(value, duration, owner, owner, locked.lockType, DepositType.SPLIT_TYPE);
            }
        }
        emit LockSplit(_weights, _tokenId);
    }

    function burn(uint256 _tokenId) external override {
        if (ownerOf(_tokenId) != msg.sender) revert NotLockOwner();
        if (__lockDetails[_tokenId].amount > 0) revert LockHoldsValue();
        _burn(_tokenId);
    }

    function _calculateEarlyExitPenalty(
        uint256 _tokenId,
        uint256 _depositedAmount
    ) internal view returns (uint256 penaltyAmount, uint256 claimableAmount) {
        uint256 currentVotingPower = balanceOfNFT(_tokenId);

        if (_depositedAmount == 0) return (0, 0);

        if (currentVotingPower == 0) {
            return (0, _depositedAmount);
        }

        penaltyAmount = currentVotingPower / 2;
        claimableAmount = _depositedAmount - penaltyAmount;
    }

    /// @notice Record global and per-user data to checkpoints. Used by VotingEscrow system.
    /// @param _tokenId NFT token ID. No user checkpoint if 0
    /// @param _oldLocked Previous locked amount / end lock time for the user
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpointLock(
        uint256 _tokenId,
        IVotingEscrowV2_Data.LockDetails memory _oldLocked,
        IVotingEscrowV2_Data.LockDetails memory _newLocked
    ) public {
        /// @dev EscrowDelegateCheckpoints.checkpoint() expects permanent locks to have an end time of 0 for slope calculations
        edStore.checkpoint(
            _tokenId,
            _oldLocked.amount.toInt128(),
            _newLocked.amount.toInt128(),
            _oldLocked.endTime,
            _newLocked.endTime
        );
    }

    /**
     * @notice Gets the balance of a lock token
     * @param _tokenId The ID of the token
     * @return The balance of the lock token
     */
    function balanceOfNFT(uint256 _tokenId) public view returns (uint256) {
        return edStore.getAdjustedEscrowBias(_tokenId, block.timestamp);
    }
}
