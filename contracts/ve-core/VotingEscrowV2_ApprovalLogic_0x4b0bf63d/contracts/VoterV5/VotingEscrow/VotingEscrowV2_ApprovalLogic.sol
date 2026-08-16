// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotingEscrowV2_ApprovalLogic} from "./IVotingEscrowV2_ApprovalLogic.sol";
import {VotingEscrowV2_Storage} from "./VotingEscrowV2_Storage.sol";
import {EscrowDelegateCheckpoints} from "./libraries/EscrowDelegateCheckpoints.sol";
import {IVotes} from "./interfaces/IVotes.sol";

// This is a stub interface to allow the logic contract to compile.
// In a delegatecall context, these functions will be available from the main contract.

contract VotingEscrowV2_ApprovalLogic is IVotingEscrowV2_ApprovalLogic, VotingEscrowV2_Storage {
    using EscrowDelegateCheckpoints for EscrowDelegateCheckpoints.EscrowDelegateStore;

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /**
     * @notice Sets or updates a conduit type configuration
     * @dev Only owner can configure conduit types (requires owner() function from main contract)
     * @param actions Array of approval actions to execute for this conduit type
     * @param description Human-readable description of the conduit type
     */
    function setConduitApprovalConfig(
        ApprovalActionType[] calldata actions,
        string calldata description
    ) external {
        address conduitAddress = msg.sender;
        require(!conduitApprovalConfig[conduitAddress].active, "Conduit already configured");
        require(actions.length > 0, "Empty actions array");

        for (uint256 i = 0; i < actions.length; i++) {
            conduitApprovalConfig[conduitAddress].actions.push(actions[i]);
        }

        conduitApprovalConfig[conduitAddress].active = true;
        conduitApprovalConfig[conduitAddress].description = description;

        emit ConduitApprovalConfigSet(conduitAddress, actions, description);
    }

    /**
     * @notice Executes a predefined set of approval actions in a single transaction
     * @dev Replaces setAccountManager with a more flexible conduit-based system
     * @param conduitAddress The conduit type to execute
     * @param tokenId The token ID (use 0 for operator-level actions)
     */
    function setConduitApproval(address conduitAddress, uint256 tokenId, bool approve) external override {
        ConduitType storage conduit = conduitApprovalConfig[conduitAddress];
        require(conduit.active, "Invalid conduit type");

        // For token-level actions, verify token ownership
        if (tokenId != 0) {
            require(ownerOf(tokenId) == msg.sender, "Not token owner");
        }

        // Execute each action in the conduit type
        for (uint256 i = 0; i < conduit.actions.length; i++) {
            _executeAction(conduit.actions[i], conduitAddress, tokenId, approve);
        }

        emit ConduitApprovalExecuted(conduitAddress, msg.sender, tokenId, conduit.actions, approve);
    }

    /**
     * @notice Internal function to execute a specific approval action
     * @param actionType The type of approval action to execute
     * @param to The address to approve/delegate to
     * @param tokenId The token ID (0 for operator-level actions)
     */
    function _executeAction(ApprovalActionType actionType, address to, uint256 tokenId, bool approve) internal {
        if (actionType == ApprovalActionType.ERC721_APPROVE) {
            _executeERC721Approve(to, tokenId, approve);
        } else if (actionType == ApprovalActionType.ERC5725_CLAIM_APPROVAL) {
            _executeERC5725ClaimApproval(to, tokenId, approve);
        } else if (actionType == ApprovalActionType.ERC5725_CLAIM_APPROVAL_FOR_ALL) {
            _executeERC5725ClaimApprovalForAll(to, approve);
        } else if (actionType == ApprovalActionType.CLAIM_REDIRECT_APPROVAL) {
            _executeClaimRedirectApproval(to, tokenId, approve);
        } else if (actionType == ApprovalActionType.CLAIM_REDIRECT_APPROVAL_FOR_ALL) {
            _executeClaimRedirectApprovalForAll(to, approve);
        } else if (actionType == ApprovalActionType.VOTING_DELEGATE) {
            _executeVotingDelegate(to, tokenId, approve);
        } else if (actionType == ApprovalActionType.VOTING_DELEGATE_FOR_ALL) {
            _executeVotingDelegateForAll(to, approve);
        } else {
            revert("Invalid action type");
        }
    }

    /**
     * @notice Executes ERC721 approve action
     * @param to The address to approve
     * @param tokenId The token ID to approve
     * @param approve Whether to approve or revoke approval
     */
    function _executeERC721Approve(address to, uint256 tokenId, bool approve) internal {
        require(tokenId != 0, "TokenId required for ERC721 approve");
        _approve(approve ? to : address(0), tokenId);
    }

    /**
     * @notice Executes ERC5725 claim approval action for a specific token
     * @param to The address to set claim approval for
     * @param tokenId The token ID for claim approval
     * @param approve Whether to approve or revoke approval
     */
    function _executeERC5725ClaimApproval(address to, uint256 tokenId, bool approve) internal {
        require(tokenId != 0, "TokenId required for ERC5725 claim approval");
        address target = approve ? to : address(0);
        _setClaimApproval(target, tokenId);
        emit ClaimApproval(msg.sender, target, tokenId, approve);
    }

    /**
     * @notice Executes ERC5725 claim approval for all tokens
     * @param to The address to set claim approval for
     * @param approve Whether to approve or revoke approval
     */
    function _executeERC5725ClaimApprovalForAll(address to, bool approve) internal {
        _setClaimApprovalForAll(to, approve);
        emit ClaimApprovalForAll(msg.sender, to, approve);
    }

    /**
     * @notice Executes claim redirect approval for a specific token
     * @param to The address to set claim redirect approval for
     * @param tokenId The token ID for claim redirect approval
     * @param approve Whether to approve or revoke approval
     */
    function _executeClaimRedirectApproval(address to, uint256 tokenId, bool approve) internal {
        require(tokenId != 0, "TokenId required for claim redirect approval");
        address target = approve ? to : address(0);
        _claimRedirectApprovalsForToken[tokenId] = target;
        emit ClaimRedirectApproval(msg.sender, target, tokenId);
    }

    /**
     * @notice Executes claim redirect approval for all tokens
     * @param to The address to set claim redirect approval for
     * @param approve Whether to approve or revoke approval
     */
    function _executeClaimRedirectApprovalForAll(address to, bool approve) internal {
        _claimRedirectApprovals[msg.sender][to] = approve;
        emit ClaimRedirectApprovalForAll(msg.sender, to, approve);
    }

    /**
     * @notice Executes voting delegation for a specific token
     * @param to The address to delegate to
     * @param tokenId The token ID to delegate
     * @param approve Whether to delegate or revoke delegation
     */
    function _executeVotingDelegate(address to, uint256 tokenId, bool approve) internal {
        require(tokenId != 0, "TokenId required for voting delegate");
        
        if (approve) {
            _delegate(tokenId, to);
        } else {
            address owner = ownerOf(tokenId);
            _delegate(tokenId, owner);
        }
    }

    /**
     * @notice Executes voting delegation for all tokens
     * @param to The address to delegate to
     * @param approve Whether to delegate or revoke delegation
     */
    function _executeVotingDelegateForAll(address to, bool approve) internal {
        if (approve) {
            _delegateForAll(msg.sender, to);
        } else {
            _delegateForAll(msg.sender, msg.sender);
        }
    }

    /**
     * @notice Sets an operator to claim rewards for a specific token ID
     * @dev Allows the token owner to delegate claim rights for a single token
     * Only the token owner can set claim redirect approval for their token
     * @param to The address that will be approved to claim rewards for the token
     * @param tokenId The token ID for which claim rights are being delegated
     * @custom:security Only token owner can call this function
     */
    function setClaimRedirectApproval(address to, uint256 tokenId) public override {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        _claimRedirectApprovalsForToken[tokenId] = to;
        emit ClaimRedirectApproval(msg.sender, to, tokenId);
    }

    /**
     * @notice Sets an operator to claim rewards for all tokens owned by the caller
     * @dev Allows the caller to delegate claim rights for all their tokens to an operator
     * This is an operator-level approval that applies to all current and future tokens
     * @param operator The address that will be approved to claim rewards for all caller's tokens
     * @param approved True to grant approval, false to revoke approval
     * @custom:security Grants broad permissions across all tokens owned by caller
     */
    function setClaimRedirectApprovalForAll(address operator, bool approved) public override {
        _claimRedirectApprovals[msg.sender][operator] = approved;
        emit ClaimRedirectApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @notice Returns the approved address for claiming rewards for a specific token
     * @dev Gets the token-level claim redirect approval for the given token ID
     * @param tokenId The token ID to check claim redirect approval for
     * @return The address approved to claim rewards for this token, or address(0) if none
     */
    function getClaimRedirectApproved(uint256 tokenId) public view returns (address) {
        return _claimRedirectApprovalsForToken[tokenId];
    }

    /**
     * @notice Checks if an operator is approved to claim rewards for all tokens of an owner
     * @dev Returns the operator-level claim redirect approval status
     * @param owner The address that owns the tokens
     * @param operator The address to check approval for
     * @return True if operator is approved for all tokens, false otherwise
     */
    function isClaimRedirectApprovedForAll(address owner, address operator) public view returns (bool) {
        return _claimRedirectApprovals[owner][operator];
    }

    function isClaimRedirectApprovedForAllOrOwner(address owner, address operator) public view returns (bool) {
        return isClaimRedirectApprovedForAll(owner, operator) || owner == operator;
    }

    /**
     * @notice Comprehensive check for claim redirect authorization
     * @dev Checks multiple authorization levels in order: ownership, token-level approval, operator-level approval
     * This is the primary function used to validate claim permissions across the system
     * @param operator The address to check authorization for
     * @param tokenId The token ID to check claim authorization for
     * @return True if operator is authorized to claim rewards for this token through any method
     * @custom:security Central authorization function - ensures proper permission hierarchy
     */
    function isApprovedClaimRedirectOrOwner(address operator, uint256 tokenId) public view returns (bool) {
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

    /**
     * @notice Delegates votes from a specific lock to a delegatee
     * @param _tokenId The ID of the lock token delegating the votes
     * @param delegatee The address to which the votes are being delegated
     */
    function _delegate(uint256 _tokenId, address delegatee) internal {
        (address fromDelegatee, address toDelegatee) = edStore.delegate(
            _tokenId,
            delegatee,
            __lockDetails[_tokenId].endTime
        );
        emit LockDelegateChanged(_tokenId, _msgSender(), fromDelegatee, toDelegatee);
    }

    function _delegateForAll(address delegator, address delegatee) internal {
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
}

