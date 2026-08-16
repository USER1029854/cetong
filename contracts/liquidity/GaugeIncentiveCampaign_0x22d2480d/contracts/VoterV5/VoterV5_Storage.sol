// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVoterV5_Storage} from "./IVoterV5_Storage.sol";
import {IVoterV5_GaugeLogic} from "./IVoterV5_GaugeLogic.sol";
import {IVoterV5_ClaimLogic} from "./IVoterV5_ClaimLogic.sol";
import {IVersionable} from "../interfaces/IVersionable.sol";

/// @title VoterV5_Storage
/// @notice This contract contains the storage variables for VoterV5.
/// @dev This contract is used to ensure both VoterV5 and VoterV5_GaugeLogic have access to the same storage variables
///  in the correct slots. They MUST both extend this.
/// - The storage layout for all version 5.x contracts MUST remain compatible for upgradeability.
contract VoterV5_Storage is IVoterV5_Storage, IVersionable {
    /// @notice The current version of the contract
    /// - 5.2.0: Add "protocolName", refactor to "oToken"
    /// - 5.2.1: Change from require to revert CustomErrors
    /// - 5.3.1: Add claim helper functions in VoterV5
    /// - 5.4.0: GaugeType improvement, use setFactory to configure factories with GaugeType
    /// - 5.4.1: Change isGaugeFactory mapping from bool to uint8 for reference counting.
    ///          This allows the same gauge factory to be used across multiple gauge types.
    ///          Storage-safe: bool and uint8 both occupy 1 byte, existing true/false values
    ///          become 1/0 counters seamlessly during upgrades.
    /// - 5.4.2: Add stale epoch check to VoterV5 to prevent voting on stale epochs.
    /// - 5.4.3: Add epoch flip check to VoterV5 to prevent voting on the epoch flip block.
    /// - 5.4.4: Allow pair and gauge factories to be set to address(0) in VoterV5 initializer.
    ///          Add claim logic contract to VoterV5 storage.
    string public constant override VERSION = "5.4.4";

    bool internal initflag;

    address public _ve; // ve token that governs these contracts
    address[] internal _factories; // Array with all the pair factories
    address public base; // underlying protocol token
    address public oToken; // option protocol token
    address[] internal _gaugeFactories; // array with all the gauge factories
    address public bribefactory; // bribe factory (internal and external)
    address public minter; // minter mints protocol tokens each epoch
    address public permissionRegistry; // registry to check accesses
    address[] public pools; // all pools viable for incentives

    uint256 public index; // (globalRewardsPerVoteWeight) gauge index
    uint256 internal DURATION; // rewards are released over 1 epoch
    uint256 public VOTE_DELAY; // delay between votes in seconds
    uint256 public MAX_VOTE_DELAY; // Max vote delay allowed

    mapping(address => uint256) internal supplyIndex; /// (gaugeRewardsPerVoteWeight) gauge    => index
    mapping(address => uint256) public claimable; /// @dev deprecated, but leaving for upgradeability
    mapping(address => address) public gauges; // pool     => gauge
    mapping(address => uint256) public gaugesDistributionTimestamp; // gauge    => last Distribution Time
    mapping(address => address) public poolForGauge; // gauge    => pool
    mapping(address => address) public internal_bribes; // gauge    => internal bribe (only fees)
    mapping(address => address) public external_bribes; // gauge    => external bribe (real bribes)
    mapping(address => mapping(address => uint256)) public votes; // nft      => pool     => votes
    mapping(address => address[]) public poolVote; // nft      => pools
    mapping(uint256 => mapping(address => uint256)) internal weightsPerEpoch; // timestamp => pool => weights
    mapping(uint256 => uint256) internal totalWeightsPerEpoch; // timestamp => total weights
    mapping(address => uint256) public lastVoted; // nft      => timestamp of last vote
    mapping(address => bool) public isGauge; // gauge    => boolean [is a gauge?]
    mapping(address => bool) public isWhitelisted; // token    => boolean [is an allowed token?]
    mapping(address => bool) public isWhitelistedPool; // token    => boolean [is an allowed token?]
    mapping(address => bool) public isAlive; // gauge    => boolean [is the gauge alive?]
    mapping(address => uint8) public isFactory; // factory  => boolean [the pair factory exists?]
    mapping(address => uint8) public isGaugeFactory; // g.factory=> usage count [how many gauge types use this factory]
    mapping(address => bool) public isGaugeDepositor; // g.factory=> boolean [the gauge factory exists?]

    IVoterV5_GaugeLogic public gaugeLogic; // gauge logic contract

    /**
     * @dev May 2024: The state variables below this have been added in VoterV5 and the gap variable reduced accordingly.
     */
    mapping(address => uint256) public gaugeKilledEpoch; // gauge => timestamp [epoch when gauge was killed]
    string public protocolName; // name of the protocol for gauge creation

    IVoterV5_ClaimLogic public claimLogic; // claim logic contract

    // Reserved space for future state variables
    uint256[47] private __gap;
}
