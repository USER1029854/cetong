// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVeArtProxy {
    function tokenURI(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 _value
    ) external view returns (string memory output);

    /// @dev Leaving for backwards compatibility
    function _tokenURI(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 _value
    ) external view returns (string memory output);
}
