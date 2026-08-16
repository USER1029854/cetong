// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {IPortalCommonTypes, IPortalTypes} from "./interfaces/IPortal.sol";
import {ICurveModule} from "./interfaces/ICurveModule.sol";
import {LibCurve} from "./libraries/Curve.sol";

/// @title  The Portal Common contract
/// @notice Stateless contract containing shared functions for curve, dex threshold, and fee calculations
contract PortalCommon is IPortalCommonTypes {
    //
    // Fee Related immutables
    //

    /// @dev Buy fee rate in basis points (bps), where 1% = 100 bps
    uint256 internal immutable FLAP_BUY_FEE;

    /// @dev Sell fee rate in basis points (bps), where 1% = 100 bps
    uint256 internal immutable FLAP_SELL_FEE;

    /// @dev Liquidity fee in basis points (0-10000, where 100 = 1%)
    uint256 internal immutable LIQUIDITY_FEE;

    /// @dev Reserve fee in basis points (0-10000, where 100 = 1%)
    uint256 internal immutable RESERVE_FEE;

    /// @dev The CurveModule used to resolve CurveType -> LibCurve.Curve. Set once via the
    ///      constructor; extracted here (not PortalBase) so PortalCommon-only inheritors
    ///      (e.g. SaleForgeBase) can also resolve curves without depending on PortalBase.
    address internal immutable CURVE_MODULE;

    constructor(
        uint256 buyFeeRate_,
        uint256 sellFeeRate_,
        uint256 liquidityFee_,
        uint256 reserveFee_,
        address curveModule_
    ) {
        FLAP_BUY_FEE = buyFeeRate_;
        FLAP_SELL_FEE = sellFeeRate_;
        LIQUIDITY_FEE = liquidityFee_;
        RESERVE_FEE = reserveFee_;
        CURVE_MODULE = curveModule_;
    }

    /// @dev get curve by type — delegates to the external CurveModule (staticcall).
    function _curveByType(CurveType curveType) internal view returns (LibCurve.Curve memory) {
        return ICurveModule(CURVE_MODULE).curveByType(curveType);
    }

    /// @dev get dex threshold by dex thresh type
    function _dexThresholdByType(DexThreshType dexThreshType) internal pure returns (uint256) {
        if (dexThreshType == DexThreshType.TWO_THIRDS) {
            return 6.67e8 ether;
        } else if (dexThreshType == DexThreshType.FOUR_FIFTHS) {
            return 8e8 ether;
        } else if (dexThreshType == DexThreshType.HALF) {
            return 5e8 ether;
        } else if (dexThreshType == DexThreshType._95_PERCENT) {
            return 9.5e8 ether;
        } else if (dexThreshType == DexThreshType._81_PERCENT) {
            return 8.1e8 ether;
        } else if (dexThreshType == DexThreshType._1_PERCENT) {
            return 0.1e8 ether;
        } else {
            // invalid return 0
            return 0;
        }
    }

    /// @dev Get buy fee based on fee profile
    /// @param profile The fee profile to use
    /// @return The buy fee in basis points (bps), where 1% = 100 bps
    function _buyFeeByProfile(FlapFeeProfile profile) internal view returns (uint256) {
        if (profile == FlapFeeProfile.FEE_GLOBAL_DEFAULT) {
            return FLAP_BUY_FEE;
        } else if (profile == FlapFeeProfile.FEE_FLAPSALE_V0) {
            return 100; // 1%
        } else if (profile == FlapFeeProfile.FEE_ZERO) {
            return 0; // 0% - no protocol fee
        } else {
            // Unknown profile, default to FEE_GLOBAL_DEFAULT
            return FLAP_BUY_FEE;
        }
    }

    /// @dev Get sell fee based on fee profile
    /// @param profile The fee profile to use
    /// @return The sell fee in basis points (bps), where 1% = 100 bps
    function _sellFeeByProfile(FlapFeeProfile profile) internal view returns (uint256) {
        if (profile == FlapFeeProfile.FEE_GLOBAL_DEFAULT) {
            return FLAP_SELL_FEE;
        } else if (profile == FlapFeeProfile.FEE_FLAPSALE_V0) {
            return 100; // 1%
        } else if (profile == FlapFeeProfile.FEE_ZERO) {
            return 0; // 0% - no protocol fee
        } else {
            // Unknown profile, default to FEE_GLOBAL_DEFAULT
            return FLAP_SELL_FEE;
        }
    }

    /// @dev Get liquidity fee based on fee profile
    /// @param profile The fee profile to use
    /// @return The liquidity fee in basis points (bps), where 1% = 100 bps
    function _liquidityFeeByProfile(FlapFeeProfile profile) internal view returns (uint256) {
        if (profile == FlapFeeProfile.FEE_GLOBAL_DEFAULT) {
            return LIQUIDITY_FEE;
        } else if (profile == FlapFeeProfile.FEE_FLAPSALE_V0) {
            return 0; // 0%
        } else if (profile == FlapFeeProfile.FEE_ZERO) {
            return 0; // 0% - no protocol fee
        } else {
            // Unknown profile, default to FEE_GLOBAL_DEFAULT
            return LIQUIDITY_FEE;
        }
    }

    /// @dev Get reserve fee based on fee profile
    /// @param profile The fee profile to use
    /// @return The reserve fee in basis points (bps), where 1% = 100 bps
    function _reserveFeeByProfile(FlapFeeProfile profile) internal view returns (uint256) {
        if (profile == FlapFeeProfile.FEE_GLOBAL_DEFAULT) {
            return RESERVE_FEE;
        } else if (profile == FlapFeeProfile.FEE_FLAPSALE_V0) {
            return 0; // 0%
        } else if (profile == FlapFeeProfile.FEE_ZERO) {
            return 0; // 0% - no protocol fee
        } else {
            // Unknown profile, default to FEE_GLOBAL_DEFAULT
            return RESERVE_FEE;
        }
    }
}
