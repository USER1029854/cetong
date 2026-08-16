// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVoterV5_Logic} from "../VoterV5/IVoterV5_Logic.sol";
import {IVoterV5_Storage} from "../VoterV5/IVoterV5_Storage.sol";

/// @title IVoterV5
/// @dev This interface is a composition of the IVoterV5_Logic and IVoterV5_Storage interfaces.
/// By composing these two interfaces, any contract that integrates IVoterV5 gains access to both the logic operations 
/// and storage getters defined in IVoterV5_Logic and IVoterV5_Storage respectively. This design also
/// circumvents the need for the VoterV5_GaugeLogic to be abstract, as it separates the concerns of
/// logic handling and state management into distinct interfaces.
interface IVoterV5 is IVoterV5_Logic, IVoterV5_Storage {}
