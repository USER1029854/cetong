// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotingEscrowV2_Data} from "./IVotingEscrowV2_Data.sol";
import {IVotingEscrowV2_Logic} from "./IVotingEscrowV2_Logic.sol";
import {IVotingEscrowV2_Storage} from "./IVotingEscrowV2_Storage.sol";
import {IERC5725_ExtendedApproval} from "./erc5725/IERC5725Upgradeable.sol";
import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

/**
 * @title Voting Escrow V2 Interface for Upgrades
 */
interface IVotingEscrowV2 is
    IVotingEscrowV2_Data,
    IVotingEscrowV2_Logic,
    IVotingEscrowV2_Storage,
    IERC5725_ExtendedApproval,
    IERC721EnumerableUpgradeable
{}
