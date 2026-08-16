// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotingEscrowV2_Data} from "./IVotingEscrowV2_Data.sol";

interface IVotingEscrowV2_ApprovalLogic {
    function setClaimRedirectApproval(address to, uint256 tokenId) external;
    function setClaimRedirectApprovalForAll(address operator, bool approved) external;
    function setConduitApproval(address conduitAddress, uint256 tokenId, bool approve) external;
    function getClaimRedirectApproved(uint256 tokenId) external view returns (address);
    function isClaimRedirectApprovedForAll(address owner, address operator) external view returns (bool);
    function isClaimRedirectApprovedForAllOrOwner(address owner, address operator) external view returns (bool);
    function isApprovedClaimRedirectOrOwner(address operator, uint256 tokenId) external view returns (bool);
    function setConduitApprovalConfig(IVotingEscrowV2_Data.ApprovalActionType[] calldata actions, string calldata description) external;
} 