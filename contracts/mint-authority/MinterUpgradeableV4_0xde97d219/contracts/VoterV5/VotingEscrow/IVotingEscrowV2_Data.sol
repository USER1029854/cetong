// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVotingEscrowV2_Data {
    struct LockDetails {
        uint256 amount; /// @dev amount of tokens locked
        uint256 startTime; /// @dev when locking started
        uint256 endTime; /// @dev when locking ends
        LockType lockType; /// @dev defines the lock type
    }

    /// @dev defines the lock type
    enum LockType {
        NON_PERMANENT, /// non permanent lock
        ROLLING, /// rolling max-lock
        PERMANENT /// permanent lock that burns the underlying
    }

    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME,
        MERGE_TYPE,
        SPLIT_TYPE
    }

    enum ApprovalActionType { 
        ERC721_APPROVE, // approve(address to, uint256 tokenId)
        ERC5725_CLAIM_APPROVAL, // setClaimApproval(address operator, bool approved, uint256 tokenId)
        ERC5725_CLAIM_APPROVAL_FOR_ALL, // setClaimApprovalForAll(address operator, bool approved)
        CLAIM_REDIRECT_APPROVAL, // setClaimRedirectApproval(address to, uint256 tokenId)
        CLAIM_REDIRECT_APPROVAL_FOR_ALL, // setClaimRedirectApprovalForAll(address operator, bool approved)
        VOTING_DELEGATE, // _delegate(uint256 tokenId, address delegatee)
        VOTING_DELEGATE_FOR_ALL // _delegateForAll(address delegator, address delegatee)
    }

    struct ConduitType {
        ApprovalActionType[] actions;
        bool active;
        string description;
    }

    event SupplyUpdated(uint256 oldSupply, uint256 newSupply);
    event LockCreated(
        uint256 indexed tokenId,
        address indexed to,
        uint256 value,
        uint256 unlockTime,
        LockType lockType
    );
    event LockUpdated(
        uint256 indexed tokenId,
        uint256 value,
        uint256 unlockTime,
        LockType lockType
    );
    event LockMerged(
        uint256 indexed fromTokenId,
        uint256 indexed toTokenId,
        uint256 totalValue,
        uint256 unlockTime,
        LockType lockType
    );
    event LockSplit(uint256[] splitWeights, uint256 indexed _tokenId);
    event LockDurationExtended(uint256 indexed tokenId, uint256 newUnlockTime, bool isPermanent);
    event LockAmountIncreased(uint256 indexed tokenId, uint256 value);
    event UnlockRolling(uint256 indexed tokenId, address indexed sender, uint256 unlockTime);
    event LockDelegateChanged(
        uint256 indexed tokenId,
        address indexed delegator,
        address fromDelegate,
        address indexed toDelegate
    );
    event EarlyExitPenalty(
        uint256 indexed tokenId,
        address indexed claimer,
        uint256 penaltyAmount,
        uint256 claimedAmount
    );
    event ClaimRedirectApprovalForAll(address indexed user, address indexed claimer, bool approved);
    event ClaimRedirectApproval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ConduitApprovalConfigSet(address indexed conduitAddress, ApprovalActionType[] actions, string description);
    event ConduitApprovalExecuted(address indexed conduitAddress, address indexed user, uint256 tokenId, ApprovalActionType[] actions, bool approve);

    error AlreadyVoted();
    error InvalidNonce();
    error InvalidDelegatee();
    error InvalidSignature();
    error InvalidSignatureS();
    error InvalidWeights();
    error LockDurationNotInFuture();
    error LockDurationTooLong();
    error LockExpired();
    error LockNotExpired();
    error LockHoldsValue();
    error LockModifiedDelay();
    error NotPermanentLock();
    error PermanentLock();
    error PermanentLockMismatch();
    error RollingLockMismatch();
    error SameNFT();
    error SignatureExpired();
    error ZeroAmount();
    error NotLockOwner();
}
