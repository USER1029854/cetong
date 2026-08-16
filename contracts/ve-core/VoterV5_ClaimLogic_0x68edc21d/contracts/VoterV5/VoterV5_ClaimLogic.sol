// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {VoterV5_Storage} from "./VoterV5_Storage.sol";
import {IVoterV5_ClaimLogic, IERC165} from "./IVoterV5_ClaimLogic.sol";
import {IVotingEscrowV2} from "./VotingEscrow/IVotingEscrowV2.sol";
import {IGauge} from "../interfaces/IGauge.sol";
import {IBribe} from "./IBribe.sol";
import {DelegateCallLib} from "../libraries/DelegateCallLib.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract VoterV5_ClaimLogic is VoterV5_Storage, IVoterV5_ClaimLogic, ERC165 {
    error NotApprovedOrOwner();
    error LengthMismatch();

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IVoterV5_ClaimLogic).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @notice Claims LP gauge rewards for the caller
     * @dev Iterates through provided gauges and claims all available rewards for msg.sender
     * @param _gauges Array of gauge addresses to claim rewards from
     */
    function claimRewards(address[] memory _gauges) external override {
        _claimRewardsFor(_gauges, msg.sender);
    }

    /**
     * @notice Claims LP gauge rewards on behalf of another address
     * @dev Requires claim approval from the _claimFor address through voting escrow
     * Only addresses with isClaimApprovedForAll permission can call this
     * @param _gauges Array of gauge addresses to claim rewards from
     * @param _claimFor The address to claim rewards for
     * @custom:security Requires proper claim delegation approval
     */
    function claimRewardsFor(address[] memory _gauges, address _claimFor) external override {
        if (!IVotingEscrowV2(_ve).isClaimApprovedForAll(_claimFor, msg.sender)) revert NotApprovedOrOwner();
        _claimRewardsFor(_gauges, _claimFor);
    }

    function _claimRewardsFor(address[] memory _gauges, address _claimFor) internal {
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGauge(_gauges[i]).getReward(_claimFor);
        }
    }

    /**
     * @notice Claims specific reward tokens from gauges for the caller
     * @dev Allows claiming only specific tokens instead of all available rewards
     * More gas efficient when only specific tokens are needed
     * @param _gauges Array of gauge addresses to claim rewards from
     * @param _tokens Array of token arrays - each inner array corresponds to tokens for the respective gauge
     */
    function claimRewardTokens(address[] memory _gauges, address[][] memory _tokens) external override {
        _claimRewardTokensFor(_gauges, _tokens, msg.sender);
    }

    function claimRewardTokensFor(
        address[] memory _gauges,
        address[][] memory _tokens,
        address _claimFor
    ) external override {
        if (!IVotingEscrowV2(_ve).isClaimApprovedForAll(_claimFor, msg.sender)) revert NotApprovedOrOwner();
        _claimRewardTokensFor(_gauges, _tokens, _claimFor);
    }

    function _claimRewardTokensFor(address[] memory _gauges, address[][] memory _tokens, address _claimFor) internal {
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGauge(_gauges[i]).getReward(_claimFor, _tokens[i]);
        }
    }

    /// @notice claim specific reward tokens for a given address and send them to the caller
    function claimRewardTokensToRecipient(
        address[] memory _gauges,
        address[][] memory _tokens,
        address _claimFor,
        address _recipient
    ) external {
        if (!IVotingEscrowV2(_ve).isClaimRedirectApprovedForAll(_claimFor, msg.sender)) revert NotApprovedOrOwner();
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGauge(_gauges[i]).getRewardToRecipient(_claimFor, _recipient, _tokens[i]);
        }
    }

    /**
     * @notice Claims bribe rewards for a specific voting escrow token ID
     * @dev Claims rewards earned by the token's voting power in governance
     * Requires ownership or claim approval for the specified token ID
     * @param _bribes Array of bribe contract addresses to claim from
     * @param _tokens Array of token arrays - tokens to claim from each bribe contract
     * @param _tokenId The voting escrow token ID to claim rewards for
     * @custom:security Requires token ownership or proper delegation approval
     */
    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external override {
        if (!IVotingEscrowV2(_ve).isApprovedClaimOrOwner(msg.sender, _tokenId)) revert NotApprovedOrOwner();
        if (_bribes.length != _tokens.length) revert LengthMismatch();
        for (uint256 i = 0; i < _bribes.length; i++) {
            IBribe(_bribes[i]).getRewardForOwner(_tokenId, _tokens[i]);
        }
    }

    /**
     * @notice Claims trading fee rewards for a specific voting escrow token ID
     * @dev Claims trading fees earned by the token's voting power allocation
     * Requires ownership or claim approval for the specified token ID
     * @param _fees Array of fee contract addresses to claim from
     * @param _tokens Array of token arrays - tokens to claim from each fee contract
     * @param _tokenId The voting escrow token ID to claim fees for
     * @custom:security Requires token ownership or proper delegation approval
     */
    function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId) external override {
        if (!IVotingEscrowV2(_ve).isApprovedClaimOrOwner(msg.sender, _tokenId)) revert NotApprovedOrOwner();
        if (_fees.length != _tokens.length) revert LengthMismatch();
        for (uint256 i = 0; i < _fees.length; i++) {
            IBribe(_fees[i]).getRewardForOwner(_tokenId, _tokens[i]);
        }
    }

    /**
     * @notice Claims bribe rewards for the caller's address across all their tokens
     * @dev Claims rewards for all tokens owned by the caller without specifying individual token IDs
     * More convenient when claiming across multiple tokens at once
     * @param _bribes Array of bribe contract addresses to claim from
     * @param _tokens Array of token arrays - tokens to claim from each bribe contract
     */
    function claimBribes(address[] memory _bribes, address[][] memory _tokens) external override {
        if (_bribes.length != _tokens.length) revert LengthMismatch();
        for (uint256 i = 0; i < _bribes.length; i++) {
            IBribe(_bribes[i]).getRewardForAddress(msg.sender, _tokens[i]);
        }
    }

    /// @notice claim fees rewards given an address
    function claimFees(address[] memory _fees, address[][] memory _tokens) external override {
        if (_fees.length != _tokens.length) revert LengthMismatch();
        for (uint256 i = 0; i < _fees.length; i++) {
            IBribe(_fees[i]).getRewardForAddress(msg.sender, _tokens[i]);
        }
    }

    /// @notice claim bribes rewards given a TokenID and send to recipient
    function claimBribesToRecipientByTokenId(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint256 _tokenId,
        address _recipient
    ) external {
        if (!IVotingEscrowV2(_ve).isApprovedClaimRedirectOrOwner(msg.sender, _tokenId)) revert NotApprovedOrOwner();
        for (uint256 i = 0; i < _bribes.length; i++) {
            IBribe(_bribes[i]).getRewardToRecipient(_tokenId, _tokens[i], _recipient);
        }
    }

    /// @notice claim bribes rewards given an address and send to recipient
    function claimBribesToRecipientByAddress(
        address[] memory _bribes,
        address[][] memory _tokens,
        address _claimFor,
        address _recipient
    ) external {
        if (!IVotingEscrowV2(_ve).isClaimRedirectApprovedForAll(_claimFor, msg.sender)) revert NotApprovedOrOwner();
        for (uint256 i = 0; i < _bribes.length; i++) {
            IBribe(_bribes[i]).getRewardForAddressToRecipient(_claimFor, _tokens[i], _recipient);
        }
    }

    /**
     * @notice Claims fee rewards for a token ID and sends them to a specified recipient
     * @dev Enables claim redirection - rewards are sent to recipient instead of token owner
     * Requires claim redirect approval or token ownership
     * @param _fees Array of fee contract addresses to claim from
     * @param _tokens Array of token arrays - tokens to claim from each fee contract
     * @param _tokenId The voting escrow token ID to claim fees for
     * @param _recipient The address to receive the claimed rewards
     * @custom:security Requires claim redirect delegation approval
     */
    function claimFeesToRecipientByTokenId(
        address[] memory _fees,
        address[][] memory _tokens,
        uint256 _tokenId,
        address _recipient
    ) external {
        if (!IVotingEscrowV2(_ve).isApprovedClaimRedirectOrOwner(msg.sender, _tokenId)) revert NotApprovedOrOwner();
        for (uint256 i = 0; i < _fees.length; i++) {
            IBribe(_fees[i]).getRewardToRecipient(_tokenId, _tokens[i], _recipient);
        }
    }

    /// @notice claim fees rewards given an address and send to recipient
    function claimFeesToRecipientByAddress(
        address[] memory _fees,
        address[][] memory _tokens,
        address _claimFor,
        address _recipient
    ) external {
        if (!IVotingEscrowV2(_ve).isClaimRedirectApprovedForAll(_claimFor, msg.sender)) revert NotApprovedOrOwner();
        for (uint256 i = 0; i < _fees.length; i++) {
            IBribe(_fees[i]).getRewardForAddressToRecipient(_claimFor, _tokens[i], _recipient);
        }
    }
} 