// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {IPortalCommonTypes} from "./IPortal.sol";
import {LibCurve} from "../libraries/Curve.sol";

/// @title ICurveModule
/// @notice External module that resolves a CurveType enum to its LibCurve.Curve parameters.
///         Extracted out of PortalBase-inheriting contracts so that adding new curve types
///         does not bloat the bytecode size of every contract in the Portal family.
interface ICurveModule is IPortalCommonTypes {
    /// @notice Get curve parameters (r, h, k) for a given curve type.
    /// @dev Reverts with InvalidCurveType if curveType is not implemented.
    function curveByType(CurveType curveType) external pure returns (LibCurve.Curve memory);
}
