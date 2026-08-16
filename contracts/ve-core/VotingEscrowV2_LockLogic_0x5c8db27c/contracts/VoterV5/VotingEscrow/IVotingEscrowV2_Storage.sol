// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IProtocolToken} from "../../interfaces/IProtocolToken.sol";
import {IVersionable} from "../../interfaces/IVersionable.sol";
import {IVotingEscrowV2_Data} from "./IVotingEscrowV2_Data.sol";

interface IVotingEscrowV2_Storage is IVersionable, IVotingEscrowV2_Data {
    /// @notice The token being locked
    function token() external view returns (IProtocolToken);
    /// @notice Total locked supply
    function supply() external view returns (uint256);
    function decimals() external view returns (uint8);
    /// @notice Immutable address for the art proxy contract
    function artProxy() external view returns (address);

    function _lockDetails(uint256) external view returns (LockDetails memory);

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    function DELEGATION_TYPEHASH() external view returns (bytes32);
    /// @notice A record of states for signing / validating signatures
    function nonces(address) external view returns (uint256);

    /// @notice tracker of current NFT id
    function totalNftsMinted() external view returns (uint256);
}
