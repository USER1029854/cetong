// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVoter {
    function length() external view returns (uint);
    function pools(uint index) external view returns (address);
    function isAlive(address _gauge) external view returns (bool);
    function ve() external view returns (address);
    function gauges(address _pair) external view returns (address);
    function isGauge(address _gauge) external view returns (bool);
    function poolForGauge(address _gauge) external view returns (address);
    function factory() external view returns (address);
    function minter() external view returns(address);
    function isWhitelisted(address token) external view returns (bool);
    function notifyRewardAmount(uint amount) external;
    function distributeAll() external;
    function distribute(address[] memory _gauges) external;
    function distributeFees(address[] memory _gauges) external;

    function internal_bribes(address _gauge) external view returns (address);
    function external_bribes(address _gauge) external view returns (address);

    function usedWeights(uint id) external view returns(uint);
    function lastVoted(uint id) external view returns(uint);
    function poolVote(uint id, uint _index) external view returns(address _pair);
    function votes(uint id, address _pool) external view returns(uint votes);
    function poolVoteLength(uint tokenId) external view returns(uint);
    
    function attachTokenToGauge(uint _tokenId, address account) external;
    function detachTokenFromGauge(uint _tokenId, address account) external;
}
