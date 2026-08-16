# TaxProcessor delegatecall targets — named, source present, behavior confirmed

The TaxProcessor clone (`TaxProcessorCore`) forwards two families of calls via
`delegatecall` to fixed helper implementations, set as immutables in the
`TaxProcessorUniV2` constructor. **This is where the `withdrawAll` sweep actually
executes.** Both show as "unverified" on the explorer by direct address lookup, but
their source *is* in this repo and their behavior is confirmed — they are not opaque.

| Immutable | Live address | What it is |
|---|---|---|
| `ADMIN_IMPL` | `0x1271D44231277202f9B34B77cD81ea59Ba7f8e20` | `TaxProcessorAdminImpl` — owner-gated admin (incl. `withdrawAll` sweep) |
| `DISPATCH_IMPL` | `0x0B46555289112A667B695DeA63D2F0a9d0564FbD` | `TaxProcessorV2DispatchImpl` — fee/market/dividend dispatch logic |

## Why they are "unverified" yet fully readable

`TaxProcessorAdminImpl` and `TaxProcessorV2DispatchImpl` are **contracts defined in
the verified source** `../TaxProcessorUniV2_impl/src/Tax/TaxProcessorBase.sol`
(lines 855 and 371 respectively). The `TaxProcessorUniV2` constructor deploys the
dispatch impl with `new TaxProcessorV2DispatchImpl(...)` and receives the admin impl
as a constructor argument. Because they were deployed *internally* by that
constructor and never submitted to the explorer separately, they carry no standalone
verification — but the bytecode running at both addresses is the compiled output of
those two contracts.

## Provenance evidence

- **ADMIN_IMPL selector match:** its runtime bytecode contains exactly the admin
  function selectors of `TaxProcessorAdminImpl` — `withdrawAll(address,address)`
  (`0x09cae2c8`), `setReceivers(address,address,address)` (`0x5d1c985b`),
  `setFeeRate(uint16)`, `setConverter(address)`, `setDividendToken(address)`,
  `setDispatchThreshold(uint256)` — all present.
- **Empirical behavior:** calling `withdrawAll(XAUt, attacker)` on the TaxProcessor
  (which delegatecalls into ADMIN_IMPL in the clone's storage context) reverts with
  `Ownable: caller is not the owner` — see `live-state/simulation-unprivileged.md`.
  The `onlyOwner` gate on the sweep therefore executes exactly as the source shows,
  against the clone's owner (the Portal).

**Read the code at:** `../TaxProcessorUniV2_impl/src/Tax/TaxProcessorBase.sol`
(`TaxProcessorAdminImpl` ≈ line 855, `withdrawAll` ≈ line 1228;
`TaxProcessorV2DispatchImpl` ≈ line 371).
