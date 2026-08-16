// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotingEscrowV2_Storage} from "./IVotingEscrowV2_Storage.sol";
import {EscrowDelegateStorage} from "./libraries/EscrowDelegateStorage.sol";
import {IVersionable} from "../../interfaces/IVersionable.sol";
import {IProtocolToken} from "../../interfaces/IProtocolToken.sol";
import {IVotingEscrowV2_ApprovalLogic} from "./IVotingEscrowV2_ApprovalLogic.sol";
import {IVotingEscrowV2_LockLogic} from "./IVotingEscrowV2_LockLogic.sol";
import {ERC5725Upgradeable} from "./erc5725/ERC5725Upgradeable.sol";

abstract contract VotingEscrowV2_Storage is IVotingEscrowV2_Storage, EscrowDelegateStorage, ERC5725Upgradeable {
    /// @notice The current version of the contract
    /// @dev changelog
    /// - 2.4.0 IVeArtProxy + IVeArtProxyHydrex integration, supports both ArtProxy interfaces
    string public constant override VERSION = "2.4.0";

    /// @notice The token being locked
    IProtocolToken public override token;
    /// @notice Total locked supply
    uint256 public override supply;
    uint8 public constant override decimals = 18;
    /// @notice Immutable address for the art proxy contract
    address public override artProxy;

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");
    /// @notice A record of states for signing / validating signatures
    mapping(address => uint256) public override nonces;

    /// @notice maps the vesting data with tokenIds
    mapping(uint256 => LockDetails) internal __lockDetails;

    function _lockDetails(uint256 _tokenId) public view override returns (LockDetails memory) {
        return __lockDetails[_tokenId];
    }

    /// @notice tracker of current NFT id
    uint256 public override totalNftsMinted = 0;

    mapping(uint256 => address) internal _claimRedirectApprovalsForToken;
    mapping(address => mapping(address => bool)) internal _claimRedirectApprovals;

    IVotingEscrowV2_ApprovalLogic public approvalLogic;
    IVotingEscrowV2_LockLogic public lockLogic;

    // Conduit System Storage
    mapping(address => ConduitType) public conduitApprovalConfig;

    /// @notice Reserved storage slots for future upgrades
    uint256[49] private __gap;

    function _endTime(uint256 tokenId) internal view override virtual returns (uint256) {
        LockDetails memory currentLock = __lockDetails[tokenId];
        if (currentLock.lockType != LockType.NON_PERMANENT) {
            return type(uint48).max;
        }
        return currentLock.endTime;
    }

    function _payout(uint256 tokenId) internal view override virtual returns (uint256) {
        return __lockDetails[tokenId].amount;
    }

    function _payoutToken(uint256 /*tokenId*/) internal view override virtual returns (address) {
        return address(token);
    }

    function _startTime(uint256 tokenId) internal view override virtual returns (uint256) {
        return __lockDetails[tokenId].startTime;
    }

    function claim(uint256 /*tokenId*/) external virtual override {}

    function isApprovedOrOwner(address /*operator*/, uint /*tokenId*/) external view virtual override returns (bool) {
        return false;
    }

    function vestedPayoutAtTime(
        uint256 tokenId,
        uint256 timestamp
    ) public view override virtual validToken(tokenId) returns (uint256 payout) {
        if (timestamp >= _endTime(tokenId)) {
            return _payout(tokenId);
        }
        return 0;
    }
}
