// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPortalTypes} from "src/interfaces/IPortal.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

/// @title QuoteRouteCodec
/// @notice SSTORE2 pack/unpack codec for a quote token's multi-hop swap route (QuoteHop[]).
/// @dev Extracted from PortalBase into an EXTERNAL (linked, DELEGATECALL'd) library so the pack/unpack
///      loops + inlined SSTORE2 read/write live in a separately-deployed contract instead of the runtime
///      bytecode of every facet that inherits PortalBase (PortalTweak, PortalTradeV2, PortalDexRouter).
///      This reclaims the room PortalTweak needs to host setQuoteSwapRoute while staying under the
///      EIP-170 limit — same motivation and pattern as LegacyPoolFinder. The functions touch no Portal
///      storage (the pointer slot stays in PortalBase); relocating them is behavior-preserving.
///
///      A route is read on every trade (preview + execute), so the whole QuoteHop[] is stored as one
///      SSTORE2 blob instead of a storage array — one EXTCODECOPY replaces N cold SLOADs per hop.
///
///      We use a fixed 48-byte packed layout per hop rather than abi.encode: abi.decode of a dynamic
///      struct array inlines a large generic decoder into every consumer. The manual fixed-stride loop
///      below is far smaller AND smaller than the storage reads it replaces. Layout per hop (big-endian,
///      byte offsets within the 48-byte record):
///        [0]      poolType  (uint8)     [1]      dexId     (uint8)
///        [2..4]   fee       (uint24)    [5..7]   tickSpacing (int24, two's complement)
///        [8..27]  tokenOut  (address)   [28..47] hooks     (address)
library QuoteRouteCodec {
    /// @dev Bytes per packed QuoteHop record in the SSTORE2 blob.
    uint256 private constant QUOTE_HOP_STRIDE = 48;

    /// @notice Route failed validation in validateAndWrite (see the checks there).
    error InvalidQuoteRoute();

    /// @notice Validate a native→quote route and, if non-empty, pack + write it to SSTORE2.
    /// @dev Kept here (not in PortalTweak) so the validation/copy loop stays out of the facet's runtime
    ///      bytecode. Reverts InvalidQuoteRoute when: the quote token is WETH; the last hop does not land
    ///      on the quote token; or any hop outputs address(0)/WETH (intermediate hops run in WETH terms
    ///      internally — native only appears implicitly as the first input).
    /// @param quoteToken The quote token the route resolves to (native→quote direction).
    /// @param hops The route hops (empty clears the route).
    /// @param weth The WETH address that may never appear as quote or any hop output.
    /// @return ptr The SSTORE2 pointer for the packed route, or address(0) when hops is empty (clear).
    function validateAndWrite(address quoteToken, IPortalTypes.QuoteHop[] calldata hops, address weth)
        public
        returns (address ptr)
    {
        // WETH is the internal wrap of native and can never be a quote token.
        if (quoteToken == weth) revert InvalidQuoteRoute();

        // An empty array clears the route; skip the remaining checks and signal "clear" to the caller.
        if (hops.length == 0) return address(0);

        // The route describes native→quote, so the last hop must land on the quote token itself.
        if (hops[hops.length - 1].tokenOut != quoteToken) revert InvalidQuoteRoute();

        // Copy calldata → memory (validating each hop) so the whole array can be packed + written.
        IPortalTypes.QuoteHop[] memory mem = new IPortalTypes.QuoteHop[](hops.length);
        for (uint256 i = 0; i < hops.length; i++) {
            if (hops[i].tokenOut == address(0) || hops[i].tokenOut == weth) revert InvalidQuoteRoute();
            mem[i] = hops[i];
        }
        ptr = write(mem);
    }

    /// @notice Read + decode the stored route from its SSTORE2 pointer. Returns an empty array when the
    ///         pointer is unset (address(0)).
    function read(address ptr) public view returns (IPortalTypes.QuoteHop[] memory hops) {
        if (ptr == address(0)) {
            return hops; // empty
        }
        bytes memory blob = SSTORE2.read(ptr);
        uint256 n = blob.length / QUOTE_HOP_STRIDE;
        hops = new IPortalTypes.QuoteHop[](n);
        for (uint256 i = 0; i < n; i++) {
            uint8 pt;
            uint8 dexId;
            uint24 fee;
            int24 tickSpacing;
            address tokenOut;
            address hooks;
            assembly ("memory-safe") {
                // base points at this hop's first byte: skip the 32-byte length word, then i*stride.
                let base := add(add(blob, 0x20), mul(i, QUOTE_HOP_STRIDE))
                let w := mload(base) // bytes [0..31] of the record, byte 0 = MSB
                pt := byte(0, w)
                dexId := byte(1, w)
                fee := and(shr(216, w), 0xFFFFFF) // bytes [2..4]
                tickSpacing := signextend(2, and(shr(192, w), 0xFFFFFF)) // bytes [5..7], sign-extended
                tokenOut := shr(96, mload(add(base, 8))) // bytes [8..27]
                hooks := shr(96, mload(add(base, 28))) // bytes [28..47]
            }
            hops[i] = IPortalTypes.QuoteHop({
                poolType: IPortalTypes.PoolType(pt),
                dexId: dexId,
                fee: fee,
                tickSpacing: tickSpacing,
                tokenOut: tokenOut,
                hooks: hooks
            });
        }
    }

    /// @notice Pack every hop (48 bytes each, see layout above) into one blob and write it to a fresh
    ///         SSTORE2 data contract; returns the pointer. Callers must handle the empty-array case
    ///         (clear the pointer) before calling this — it always writes.
    function write(IPortalTypes.QuoteHop[] memory hops) public returns (address ptr) {
        bytes memory blob;
        for (uint256 i = 0; i < hops.length; i++) {
            IPortalTypes.QuoteHop memory h = hops[i];
            blob = abi.encodePacked(
                blob,
                uint8(h.poolType),
                h.dexId,
                h.fee, // uint24 → 3 bytes
                h.tickSpacing, // int24 → 3 bytes (two's complement)
                h.tokenOut, // address → 20 bytes
                h.hooks // address → 20 bytes
            );
        }
        ptr = SSTORE2.write(blob);
    }
}
