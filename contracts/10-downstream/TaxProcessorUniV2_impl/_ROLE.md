# TaxProcessorUniV2 implementation

- **Address:** `0x886301F6A7082C283086e7Fd63C3cAbB12a57d40`
- **Kind:** logic (behind TaxProcessor clone)
- **Verified:** True

## Role

Tax processing logic. _swapTokensForQuote uses amountOutMin=0 (no slippage guard). withdrawAll(token,to) onlyOwner sweep. Delegates admin to TaxProcessorAdminImpl, dispatch to TaxProcessorV2DispatchImpl.
