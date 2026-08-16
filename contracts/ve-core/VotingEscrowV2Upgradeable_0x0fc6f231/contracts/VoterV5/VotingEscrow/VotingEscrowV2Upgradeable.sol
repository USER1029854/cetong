// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IERC5725Upgradeable} from "./erc5725/IERC5725Upgradeable.sol";
import {IERC721EnumerableUpgradeable, ERC721EnumerableUpgradeable, IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC5725Upgradeable} from "./erc5725/ERC5725Upgradeable.sol";

import {IProtocolToken} from "../../interfaces/IProtocolToken.sol";
import {IVeArtProxy} from "../../VeArtProxy/IVeArtProxy.sol";
import {IVeArtProxyHydrex} from "../../VeArtProxy/IVeArtProxyHydrex.sol";
import {SafeCastLibrary} from "./libraries/SafeCastLibrary.sol";
import {EscrowDelegateCheckpoints, Checkpoints} from "./libraries/EscrowDelegateCheckpoints.sol";
import {VotingEscrowV2_Storage} from "./VotingEscrowV2_Storage.sol";
import {IVotingEscrowV2_ApprovalLogic} from "./IVotingEscrowV2_ApprovalLogic.sol";
import {DelegateCallLib} from "../../libraries/DelegateCallLib.sol";
import {IVotingEscrowV2_LockLogic} from "./IVotingEscrowV2_LockLogic.sol";
import {IVotingEscrowV2_Logic, IVotes} from "./IVotingEscrowV2_Logic.sol";
import {IVotingEscrowV2_Data} from "./IVotingEscrowV2_Data.sol";
import {IVotingEscrowV2} from "./IVotingEscrowV2.sol";

/**
 * @title VotingEscrowV2Upgradeable
 * @dev This contract is used for locking tokens and voting.
 * - The storage layout for all version 2.x contracts MUST remain compatible for upgradeability.
 * - tokenIds always have a delegatee, with the owner being the default (see createLock)
 * - On transfers, delegation is reset. (See _update)
 *
 * @custom:limitations
 * - DOES NOT support feeOnTransfer for lock token: token
 * - EscrowDelegateCheckpoints.checkpoint() creates a minimum token decimal limitation
 *   - Because point.slope = (amount) / MAX_TIME, if amount is less than 63,072,000 (two years), the slope will be divided to 0.
 *   - This limitation means that the minimum token decimal should be 8, but more is recommended.
 * - getAccountDelegates() may run out of gas if the account has too many tokens.
 * - ReentrancyGuard is used over ReentrancyGuardUpgradeable for upgradeability.
 */
contract VotingEscrowV2Upgradeable is
    IVotingEscrowV2_Data,
    IVotingEscrowV2_Logic,
    VotingEscrowV2_Storage,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeCastLibrary for uint256;
    using EscrowDelegateCheckpoints for EscrowDelegateCheckpoints.EscrowDelegateStore;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /**
     * @notice The constructor is disabled for this upgradeable contract.
     */
    constructor() {
        /// @dev Disable the initializers for implementation contracts to ensure that the contract is not left uninitialized.
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _name The name to set for the token.
     * @param _symbol The symbol to set for the token.
     * @param version The version of the contract.
     * @param mainToken The main token address that will be locked in the escrow.
     * @param _artProxy The address of the art proxy contract.
     * @param _approvalLogic The address of the approval logic contract.
     * @param _lockLogic The address of the lock logic contract.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        string memory version,
        IProtocolToken mainToken,
        address _artProxy,
        address _approvalLogic,
        address _lockLogic
    ) public initializer {
        __ERC5725_init(_name, _symbol);
        __EIP712_init(_name, version);
        __ReentrancyGuard_init();
        // Validate and set the main token address
        token = mainToken;
        token.totalSupply(); // Validate token address
        // Validate and set the art proxy address
        artProxy = _artProxy;
        _tokenURI(0); // Validate art proxy address
        // Reset MAX_TIME in proxy storage
        MAX_TIME = uint256(uint128(EscrowDelegateCheckpoints.MAX_TIME));
        approvalLogic = IVotingEscrowV2_ApprovalLogic(_approvalLogic);
        lockLogic = IVotingEscrowV2_LockLogic(_lockLogic);
    }

    modifier checkAuthorized(uint256 _tokenId) {
        address owner = _ownerOf(_tokenId);
        if (owner == address(0)) {
            revert ERC721NonexistentToken(_tokenId);
        }
        address sender = _msgSender();
        if (!_isAuthorized(owner, sender, _tokenId)) {
            revert ERC721InsufficientApproval(sender, _tokenId);
        }
        _;
    }

    /// @dev Returns current token URI metadata
    /// @param _tokenId Token ID to fetch URI for.
    function tokenURI(uint _tokenId) public view override validToken(_tokenId) returns (string memory) {
        return _tokenURI(_tokenId);
    }

    /// @dev Returns current token URI metadata
    /// @param _tokenId Token ID to fetch URI for.
    function _tokenURI(uint _tokenId) internal view returns (string memory) {
        LockDetails memory _locked = __lockDetails[_tokenId];
            try IVeArtProxyHydrex(artProxy)._tokenURI(
                _tokenId,
                balanceOfNFT(_tokenId),
                _locked.endTime,
                uint256(int256(_locked.amount)),
                _locked.lockType
            ) returns (string memory uri) {
                return uri;
            } catch {
                return IVeArtProxy(artProxy)._tokenURI(
                    _tokenId,
                    balanceOfNFT(_tokenId),
                    _locked.endTime,
                    uint256(int256(_locked.amount))
                );
            }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool supported) {
        return interfaceId == type(IVotingEscrowV2).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-_beforeTokenTransfer}.
     * Clears the approval of a given `tokenId` when the token is transferred or burned.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            uint256 tokenId = firstTokenId + i;
            /// @dev Frontrun protection can be added here
            if (from != to) {
                /// @dev Clear claim redirect approval on transfer
                delete _claimRedirectApprovalsForToken[tokenId];

                /// @dev Sets delegatee to new owner on transfers
                (address oldDelegatee, address newDelegatee) = edStore.delegate(
                    tokenId,
                    to,
                    __lockDetails[tokenId].endTime
                );
                emit DelegateChanged(to, oldDelegatee, newDelegatee);
                emit LockDelegateChanged(tokenId, to, oldDelegatee, newDelegatee);
            }
        }
    }

    /**
     * @notice Creates a lock for the sender
     * @param _value The total assets to be locked over time
     * @param _lockDuration Duration in seconds of the lock
     * @param _lockType Whether the lock is permanent or not
     * @return The id of the newly created token
     */
    function createLock(
        uint256 _value,
        uint256 _lockDuration,
        LockType _lockType
    ) external nonReentrant returns (uint256) {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(IVotingEscrowV2_LockLogic.createLock.selector, _value, _lockDuration, _lockType)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Creates a lock for a specified address
     * @param _value The total assets to be locked over time
     * @param _lockDuration Duration in seconds of the lock
     * @param _to The receiver of the lock
     * @param _lockType Whether the lock is permanent or not
     * @return The id of the newly created token
     */
    function createLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        LockType _lockType
    ) external nonReentrant returns (uint256) {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(
                IVotingEscrowV2_LockLogic.createLockFor.selector,
                _value,
                _lockDuration,
                _to,
                _lockType
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Creates a lock for a specified address with a specified delegatee
     * @param _value The total assets to be locked over time
     * @param _lockDuration Duration in seconds of the lock
     * @param _to The receiver of the lock
     * @param _delegatee The delegatee of the lock
     * @param _lockType Whether the lock is permanent or not
     * @return The id of the newly created token
     */
    function createDelegatedLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        address _delegatee,
        LockType _lockType
    ) external nonReentrant returns (uint256) {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(
                IVotingEscrowV2_LockLogic.createDelegatedLockFor.selector,
                _value,
                _lockDuration,
                _to,
                _delegatee,
                _lockType
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Creates a lock for a specified address with a specified delegatee that has claimable permissions
     * @param _value The total assets to be locked over time
     * @param _lockDuration Duration in seconds of the lock
     * @param _to The receiver of the lock
     * @param _delegatee The delegatee of the lock who also gets claim redirect approval
     * @param _lockType Whether the lock is permanent or not
     * @return The id of the newly created token
     */
    function createClaimableLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        address _delegatee,
        LockType _lockType
    ) external nonReentrant returns (uint256) {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(
                IVotingEscrowV2_LockLogic.createClaimableLockFor.selector,
                _value,
                _lockDuration,
                _to,
                _delegatee,
                _lockType
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Updates the global checkpoint
     */
    function globalCheckpoint() public nonReentrant {
        return edStore.globalCheckpoint();
    }

    /**
     * @notice Alias for globalCheckpoint()
     */
    function checkpoint() external override {
        globalCheckpoint();
    }

    /**
     * @notice Updates the checkpoint for a delegatee
     * @param _delegateeAddress The address of the delegatee
     */
    function checkpointDelegatee(address _delegateeAddress) external nonReentrant {
        edStore.baseCheckpointDelegatee(_delegateeAddress);
    }

    /// @notice Deposit `_value` tokens for `_tokenId` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user
    /// @param _tokenId lock NFT
    /// @param _value Amount to add to user's lock
    function increaseAmount(uint256 _tokenId, uint256 _value) external nonReentrant {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(IVotingEscrowV2_LockLogic.increaseAmount.selector, _tokenId, _value)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /**
     * @notice Increases the unlock time of a non-permanent lock
     * @param _tokenId The id of the token to increase the unlock time for
     * @param _lockDuration The new duration of the lock
     * @param _permanent Whether the lock is permanent or not
     */
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration, bool _permanent) external nonReentrant {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(
                IVotingEscrowV2_LockLogic.increaseUnlockTime.selector,
                _tokenId,
                _lockDuration,
                _permanent
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /**
     * @notice Unlocks a permanent lock
     * @param _tokenId The id of the token to unlock
     */
    function unlockRolling(uint256 _tokenId) external nonReentrant {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(IVotingEscrowV2_LockLogic.unlockRolling.selector, _tokenId)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /**
     * @notice Claims the payout for a token
     * @param _tokenId The id of the token to claim the payout for
     */
    function claim(uint256 _tokenId) external override nonReentrant {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(IVotingEscrowV2_LockLogic.claim.selector, _tokenId)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /**
     * @notice Merges two tokens together
     * @param _from The id of the token to merge from
     * @param _to The id of the token to merge to
     */
    function merge(uint256 _from, uint256 _to) external nonReentrant {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(IVotingEscrowV2_LockLogic.merge.selector, _from, _to)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /**
     * @notice Splits a token into multiple tokens
     * @dev WARN split locks will reset delegation to the owner
     * @param _weights The percentages to split the token into
     * @param _tokenId The id of the token to split
     */
    function split(uint256[] memory _weights, uint256 _tokenId) external nonReentrant {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(IVotingEscrowV2_LockLogic.split.selector, _weights, _tokenId)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /**
     * @notice Burns a token
     * @param _tokenId The ids of the tokens to burn
     */
    function burn(uint256 _tokenId) external nonReentrant {
        (bool success, bytes memory result) = address(lockLogic).delegatecall(
            abi.encodeWithSelector(IVotingEscrowV2_LockLogic.burn.selector, _tokenId)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /*///////////////////////////////////////////////////////////////
                           GAUGE REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the balance of a lock token
     * @param _tokenId The ID of the token
     * @return The balance of the lock token
     */
    function balanceOfNFT(uint256 _tokenId) public view returns (uint256) {
        return edStore.getAdjustedEscrowBias(_tokenId, block.timestamp);
    }

    /**
     * @notice Gets the balance of a lock token at a specific timestamp
     * @param _tokenId The ID of the token
     * @param _timestamp The timestamp to get the balance at
     * @return The balance of the lock token at the specified timestamp
     */
    function balanceOfNFTAt(uint256 _tokenId, uint256 _timestamp) external view returns (uint256) {
        return edStore.getAdjustedEscrowBias(_tokenId, _timestamp);
    }

    /**
     * @notice Gets the past escrow point for a token at a specific timestamp
     * @param _tokenId The ID of the token
     * @param _timestamp The timestamp to get the past escrow point at
     * @return The escrow point and timestamp of the past escrow point
     */
    function getPastEscrowPoint(
        uint256 _tokenId,
        uint256 _timestamp
    ) external view override returns (Checkpoints.Point memory, uint48) {
        return edStore.getAdjustedEscrow(_tokenId, _timestamp);
    }

    /**
     * @notice Gets the first escrow point for a token
     * @param _tokenId The ID of the token
     * @return The escrow point and timestamp of the first escrow point
     */
    function getFirstEscrowPoint(uint256 _tokenId) external view override returns (Checkpoints.Point memory, uint48) {
        return edStore.getFirstEscrowPoint(_tokenId);
    }

    /**
     * @notice Gets the total supply of the lock tokens
     * @return The total supply of the lock tokens
     */
    function totalSupply() public view override(ERC721EnumerableUpgradeable) returns (uint256) {
        return edStore.getAdjustedGlobalVotes(block.timestamp.toUint48());
    }

    /*///////////////////////////////////////////////////////////////
                           @dev See {IVotes}.
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the votes for a delegatee
     * @param account The address of the delegatee
     * @return The number of votes the delegatee has
     */
    function getVotes(address account) external view override(IVotes) returns (uint256) {
        return edStore.getAdjustedVotes(account, block.timestamp.toUint48());
    }

    /**
     * @notice Gets the past votes for a delegatee at a specific time point
     * @param account The address of the delegatee
     * @param timepoint The time point to get the votes at
     * @return The number of votes the delegatee had at the time point
     */
    function getPastVotes(address account, uint256 timepoint) external view override(IVotes) returns (uint256) {
        return edStore.getAdjustedVotes(account, timepoint.toUint48());
    }

    /**
     * @notice Gets the total supply at a specific time point
     * @param _timePoint The time point to get the total supply at
     * @return The total supply at the time point
     */
    function getPastTotalSupply(uint256 _timePoint) external view override(IVotes) returns (uint256) {
        return edStore.getAdjustedGlobalVotes(_timePoint.toUint48());
    }

    /**
     * @notice Delegates votes to a delegatee
     * @param delegatee The account to delegate votes to
     */
    function delegate(address delegatee) external override(IVotes) nonReentrant {
        _delegate(_msgSender(), delegatee);
    }

    /**
     * @notice Gets the delegate of a delegatee
     * @dev This function implements IVotes interface.
     *  An account can have multiple delegates in this contract. If multiple
     *  different delegates are found, this function returns address(1) to
     *  indicate that there is not a single unique delegate.
     * @param account The delegatee to get the delegate of
     * @return The delegate of the delegatee, or address(1) if multiple different delegates are found
     */
    function delegates(address account) external view override(IVotes) returns (address) {
        address delegatee = address(0);
        uint256 balance = balanceOf(account);
        /// @dev out-of-gas protection
        uint256 runs = 50 > balance ? balance : 50;
        for (uint256 i = 0; i < runs; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(account, i);
            address currentDelegatee = edStore.getEscrowDelegatee(tokenId);
            /// @dev Hacky way to check if the delegatee is the same for all locks
            if (delegatee == address(0)) {
                delegatee = currentDelegatee;
            } else if (delegatee != currentDelegatee) {
                return address(1);
            }
        }
        return delegatee;
    }

    /**
     * @notice Delegates votes from a specific lock to a delegatee
     * @param _tokenId The ID of the lock token delegating the votes
     * @param delegatee The address to which the votes are being delegated
     */
    function delegate(uint256 _tokenId, address delegatee) external checkAuthorized(_tokenId) {
        (address fromDelegatee, address toDelegatee) = edStore.delegate(
            _tokenId,
            delegatee,
            __lockDetails[_tokenId].endTime
        );
        emit LockDelegateChanged(_tokenId, _msgSender(), fromDelegatee, toDelegatee);
    }

    /**
     * @notice Delegates votes for a list of locks to a delegatee
     * @param tokenIds The list of lock token IDs delegating the votes
     * @param delegatee The address to which the votes are being delegated
     */
    function delegateBatch(uint256[] calldata tokenIds, address delegatee) external {
        address delegator = _msgSender();
        address fromDelegate = address(0);
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = tokenIds[i];
            address owner = _ownerOf(tokenId);
            if (owner == address(0)) {
                revert ERC721NonexistentToken(tokenId);
            }
            if (!_isAuthorized(owner, delegator, tokenId)) {
                revert ERC721InsufficientApproval(delegator, tokenId);
            }
            (address oldDelegate, address newDelegate) = edStore.delegate(
                tokenId,
                delegatee,
                __lockDetails[tokenId].endTime
            );
            emit LockDelegateChanged(tokenId, delegator, oldDelegate, newDelegate);
            if (fromDelegate == address(0)) {
                fromDelegate = oldDelegate;
            } else if (fromDelegate != address(1)) {
                if (fromDelegate != oldDelegate) {
                    fromDelegate = address(1);
                }
            }
        }
        emit DelegateChanged(delegator, fromDelegate, delegatee);
    }

    /**
     * @notice Gets the delegatee of a given lock
     * @param tokenId The ID of the lock token
     * @return The address of the delegatee for the specified token
     */
    function getLockDelegatee(uint256 tokenId) external view returns (address) {
        return edStore.getEscrowDelegatee(tokenId);
    }

    /**
     * @notice Gets all delegates of a delegatee
     * @param account The delegatee to get the delegates of
     * @return An array of all delegates of the delegatee
     */
    function getAccountDelegates(address account) external view returns (address[] memory) {
        uint256 balance = balanceOf(account);
        address[] memory allDelegates = new address[](balance);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(account, i);
            allDelegates[i] = edStore.getEscrowDelegatee(tokenId);
        }
        return allDelegates;
    }

    /**
     * @notice Public function to get the delegatee of a lock
     * @param tokenId The ID of the token
     * @param timestamp The timestamp to get the delegate at
     * @return The address of the delegate
     */
    function delegates(uint256 tokenId, uint48 timestamp) external view returns (address) {
        return edStore.getEscrowDelegateeAtTime(tokenId, timestamp);
    }

    /**
     * @notice Delegates votes from an owner to an delegatee
     * @param delegator The owner of the tokenId delegating votes
     * @param delegatee The account to delegate votes to
     */
    function _delegate(address delegator, address delegatee) internal {
        uint256 balance = balanceOf(delegator);
        address fromDelegate = address(0);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(delegator, i);
            (address oldDelegate, address newDelegate) = edStore.delegate(
                tokenId,
                delegatee,
                __lockDetails[tokenId].endTime
            );
            emit LockDelegateChanged(tokenId, delegator, oldDelegate, newDelegate);
            /// @dev Hacky way to check if the delegatee is the same for all locks
            if (fromDelegate == address(0)) {
                fromDelegate = oldDelegate;
            } else if (fromDelegate != address(1)) {
                if (fromDelegate != oldDelegate) {
                    fromDelegate = address(1);
                }
            }
        }
        emit DelegateChanged(delegator, fromDelegate, delegatee);
    }

    /*///////////////////////////////////////////////////////////////
                           ERC5725Upgradeable
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC5725Upgradeable
    function vestedPayoutAtTime(
        uint256 tokenId,
        uint256 timestamp
    ) public view override validToken(tokenId) returns (uint256 payout) {
        if (timestamp >= _endTime(tokenId)) {
            return _payout(tokenId);
        }
        return 0;
    }

    /// @dev All vested tokens are claimable
    function claimablePayout(uint256 tokenId) public view override validToken(tokenId) returns (uint256) {
        return vestedPayout(tokenId);
    }

    /// @inheritdoc ERC5725Upgradeable
    function _payoutToken(uint256 /*tokenId*/) internal view override returns (address) {
        return address(token);
    }

    /// @inheritdoc ERC5725Upgradeable
    function _payout(uint256 tokenId) internal view override returns (uint256) {
        return __lockDetails[tokenId].amount;
    }

    /// @inheritdoc ERC5725Upgradeable
    function _startTime(uint256 tokenId) internal view override returns (uint256) {
        return __lockDetails[tokenId].startTime;
    }

    /// @inheritdoc ERC5725Upgradeable
    function _endTime(uint256 tokenId) internal view override returns (uint256) {
        LockDetails memory currentLock = __lockDetails[tokenId];
        if (currentLock.lockType != LockType.NON_PERMANENT) {
            return type(uint48).max;
        }
        return currentLock.endTime;
    }

    /**
     * @notice Gets the lock details of a token
     * @param _tokenId The ID of the token
     * @return The lock details of the token
     */
    function lockDetails(uint256 _tokenId) external view returns (LockDetails memory) {
        return __lockDetails[_tokenId];
    }

    /**
     * @notice Checks if a user is approved or the owner of a token
     * @param user The address of the user
     * @param tokenId The ID of the token
     * @return True if the user is approved or the owner, false otherwise
     */
    function isApprovedOrOwner(address user, uint tokenId) external view override returns (bool) {
        return _isAuthorized(ownerOf(tokenId), user, tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                           REWARD CLAIM APPROVAL SYSTEM
    //////////////////////////////////////////////////////////////*/

    /// @notice Approve a specific address to claim rewards for a specific token (token-level)
    function setClaimRedirectApproval(address to, uint256 tokenId) external override {
        (bool success, bytes memory result) = address(approvalLogic).delegatecall(
            abi.encodeWithSelector(IVotingEscrowV2_ApprovalLogic.setClaimRedirectApproval.selector, to, tokenId)
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice Approve or revoke an address to claim rewards on your behalf (operator-level)
    function setClaimRedirectApprovalForAll(address operator, bool approved) external override {
        (bool success, bytes memory result) = address(approvalLogic).delegatecall(
            abi.encodeWithSelector(
                IVotingEscrowV2_ApprovalLogic.setClaimRedirectApprovalForAll.selector,
                operator,
                approved
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice Get the approved address for claim redirect for a specific token (token-level)
    function getClaimRedirectApproved(uint256 tokenId) public view override returns (address) {
        return _claimRedirectApprovalsForToken[tokenId];
    }

    /// @notice Check if an address is approved for claim redirect for a user (operator-level)
    /// @dev Similar to isApprovedForAll() but for claim redirect
    function isClaimRedirectApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _claimRedirectApprovals[owner][operator];
    }

    function isClaimRedirectApprovedForAllOrOwner(address owner, address operator) public view override returns (bool) {
        return isClaimRedirectApprovedForAll(owner, operator) || owner == operator;
    }

    /// @notice Check if an address can claim redirect for a specific token (combines all approval levels)
    /// @dev Checks token-level approval, operator-level approval, and ERC-721 approvals
    function isApprovedClaimRedirectOrOwner(address operator, uint256 tokenId) public view override returns (bool) {
        address owner = ownerOf(tokenId);

        // Check if operator is the owner
        if (owner == operator) {
            return true;
        }

        // Check token-level approval
        if (_claimRedirectApprovalsForToken[tokenId] == operator) {
            return true;
        }

        // Check operator-level approval
        if (_claimRedirectApprovals[owner][operator]) {
            return true;
        }

        return false;
    }

    /*///////////////////////////////////////////////////////////////
                           CONDUIT APPROVAL SYSTEM
    //////////////////////////////////////////////////////////////*/

    function getConduitApprovalConfig(
        address conduitAddress
    ) external view returns (ApprovalActionType[] memory actions, bool active, string memory description) {
        ConduitType storage conduit = conduitApprovalConfig[conduitAddress];
        return (conduit.actions, conduit.active, conduit.description);
    }

    function setConduitApprovalConfig(
        ApprovalActionType[] calldata actions,
        string calldata description
    ) external override {
        (bool success, bytes memory result) = address(approvalLogic).delegatecall(
            abi.encodeWithSelector(
                IVotingEscrowV2_ApprovalLogic.setConduitApprovalConfig.selector,
                actions,
                description
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }

    /// @notice Delegate voting power and approve for claim redirection in a single transaction
    function setConduitApproval(address conduitAddress, uint256 tokenId, bool approve) external override nonReentrant {
        (bool success, bytes memory result) = address(approvalLogic).delegatecall(
            abi.encodeWithSelector(
                IVotingEscrowV2_ApprovalLogic.setConduitApproval.selector,
                conduitAddress,
                tokenId,
                approve
            )
        );
        DelegateCallLib.handleDelegateCallResult(success, result);
    }
}
