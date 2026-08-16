// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVotingEscrowV2_Data} from "./IVotingEscrowV2_Data.sol";

interface IVotingEscrowV2_LockLogic {
    function createLock(
        uint256 _value,
        uint256 _lockDuration,
        IVotingEscrowV2_Data.LockType _lockType
    ) external returns (uint256);

    function createLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        IVotingEscrowV2_Data.LockType _lockType
    ) external returns (uint256);

    function createDelegatedLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        address _delegatee,
        IVotingEscrowV2_Data.LockType _lockType
    ) external returns (uint256);

    function createClaimableLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        address _delegatee,
        IVotingEscrowV2_Data.LockType _lockType
    ) external returns (uint256);

    function increaseAmount(uint256 _tokenId, uint256 _value) external;

    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration, bool _permanent) external;

    function unlockRolling(uint256 _tokenId) external;

    function claim(uint256 _tokenId) external;

    function merge(uint256 _from, uint256 _to) external;

    function split(uint256[] memory _weights, uint256 _tokenId) external;

    function burn(uint256 _tokenId) external;
}
