// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVotingEscrowV2_Data} from "../VoterV5/VotingEscrow/IVotingEscrowV2_Data.sol";

interface IVeArtProxyHydrex {
    function tokenURI(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 _value,
        IVotingEscrowV2_Data.LockType _lockType
    ) external view returns (string memory output);

    function _tokenURI(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 _value,
        IVotingEscrowV2_Data.LockType _lockType
    ) external view returns (string memory output);
}
