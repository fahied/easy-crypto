---
advance:
  id: "ADV-CORE-SERVICES-009"
  title: "Fix History tab missing balances — use static asset list instead of dynamic discovery"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "core-models"]
  started_at: "2026-08-17T00:00:00Z"
  implementation_completed_at: ~
  review_time_estimate_minutes: 15
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: ~
  risk_flags: []
  evidence: []
  model_usage: []
  status: planned
---

## Objective

The History tab shows incomplete P&L because asset discovery relies on the live account
balance endpoint, which omits assets with zero balance. Fully-sold positions disappear
from the sync list, and their trade history is never re-fetched.

The user trades a fixed set of ~17 assets. Instead of dynamic discovery from the API,
use a static symbol list and always sync every symbol regardless of current balance.

## Behavioral Change

- **Before**: Asset list is built from `/api/v3/account?omitZeroBalances=true` (spot) and
  `netAsset > threshold` filters (margin). Closed positions are silently skipped.
- **After**: A static list of known trading symbols is always included in the sync set.
  Closed positions are re-discovered and their incremental `fromId` cursor fetches only
  new trades since last sync.

## Root Cause

`TradeImportService.sync` builds the asset list from the balance endpoint response.
Binance omits zero-balance assets. `existingSync` keys provide partial rescue but only
for symbols whose cursor survived a previous sync. The underlying problem is that
**discovery should not depend on current balance at all** for a known set of assets.

## Design

### Static asset list

Replace dynamic balance-based discovery with a static list of USDT trading pairs:

```swift
private static let knownAssets: [String] = [
    "ADA", "ALLO", "BANK", "BCH", "BNB", "BTC", "DEXE", "ETH",
    "HYPER", "IOTA", "LTC", "MET", "MMT", "NEAR", "SENT",
    "SOL", "TRX", "XRP"
]
```

The sync flow becomes:

1. Start with `knownAssets` as the base symbol list (`"\(asset)USDT"`)
2. Union with balance-discovered assets (catches new assets not yet in the static list)
3. Union with `existingSync` keys (catches symbols from previous sessions)
4. Deduplicate → sorted → fetch trades per symbol with incremental `fromId`

The balance endpoint is still called (needed for current holdings/quantities) but its
result no longer gates which symbols get synced.

### Where to apply

1. **`TradeImportService.sync`** (spot): prepend `knownAssets` to the asset set before
   the fetch loop. Balance discovery becomes additive, not primary.
2. **`MarginTradeImportService.syncCrossMargin`**: same static list applied to cross-margin
   trade fetching.
3. **`MarginTradeImportService.syncIsolatedMargin`**: same static list applied to
   isolated-margin trade fetching.

### Adding new assets

When the user starts trading a new asset not in the static list, the balance-discovered
assets path picks it up automatically. The static list is a floor, not a ceiling.

## Implementation Tasks

### tidy
- None — implementation is additive.

### test
- [ ] `TradeImportServiceTests`: all static list symbols are synced even when account
      balance is empty (all positions closed).
- [ ] `TradeImportServiceTests`: balance-discovered asset not in static list is still synced.
- [ ] `TradeImportServiceTests`: `existingSync` symbols not in static list or balances are
      still synced (backward compat).
- [ ] `TradeImportServiceTests`: no duplicate symbols when all three sources overlap.
- [ ] `MarginTradeImportServiceTests`: static list symbols synced for cross-margin.
- [ ] `MarginTradeImportServiceTests`: static list symbols synced for isolated-margin.

### feat
- [ ] `TradeImportService.sync`: add `knownAssets` constant, union it into the asset set
      before the fetch loop. Balance discovery becomes additive.
- [ ] `MarginTradeImportService.syncCrossMargin`: add same static list, union into symbol
      set before trade fetch.
- [ ] `MarginTradeImportService.syncIsolatedMargin`: add same static list, union into
      symbol set before trade fetch.

## Risk + Rollback

- **Risk**: extra API calls for static list symbols that have no new trades. Bounded by
  ~17 symbols, and incremental `fromId` means Binance returns empty arrays instantly.
- **Risk**: user trades a new asset not in the static list and expects it to appear. The
  balance-discovered path handles this, but there may be a one-sync delay. Documented
  behavior.
- **Rollback**: remove the `knownAssets` union. Discovery reverts to balance-only. No
  schema changes.

## Dependencies

- Blocked by: none.
- Blocks: ADV-TRADE-HISTORY-003 (History tab accuracy depends on complete sync).
- Related: ADV-CORE-SERVICES-006 (margin sync), ADV-TRADE-HISTORY-003 (History tab).

## Check for Understanding

1. Why does `omitZeroBalances=true` on `/api/v3/account` cause closed positions to
   disappear, and how does a static list prevent this?
2. How does the incremental `fromId` cursor make syncing a static list of ~17 symbols
   cheap in steady state?
3. Why is the balance endpoint still called if the static list drives symbol discovery?
4. How does the union with `existingSync` keys and balance-discovered assets ensure
   backward compatibility with symbols outside the static list?
