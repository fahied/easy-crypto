---
advance:
  id: ADV-CORE-SERVICES-006
  title: Margin trade import service — cross-margin and isolated-margin incremental sync
  system: easycrypto-core
  primary_component: core-services
  components:
  - core-services
  - core-models
  started_at: 2026-08-07T09:00:00Z
  started_by: null
  implementation_completed_at: 2026-08-08T03:25:08.925712Z
  implementation_completed_by: null
  updated_by: null
  archived_at: null
  archived_by: null
  review_time_estimate_minutes: 30
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  status: planned
---

## Objective

Add a `MarginTradeImportService` that mirrors `TradeImportService` but fetches trades
from Binance's margin REST endpoints (`/sapi/v1/margin/myTrades`) for both cross-margin
and isolated-margin trading modes. It reuses the pagination, rate-limit retry, and
`SyncMetadata` patterns already proven in `TradeImportService`. Depends on
ADV-CORE-SERVICES-005 (margin API endpoints).

## Behavioral Change

After this advance:

- New `MarginTradeImportService` (struct-with-closures) has a `sync` closure:
  `(_ mode: TradingMode, _ existingSync: [Int64: Int64]) async throws -> TradeImportResult`
  - The key map is `isolatedMarginKey → lastTradeId` for isolated-margin
    (since isolated-margin trades are scoped per-isolated-symbol, not per-trading-symbol)
  - The key map is `"cross" → lastTradeId` for cross-margin (single global sync cursor)
- The service calls `fetchMarginMyTrades` from `BinanceAPIClient` with the correct
  `isIsolated` flag.
- Imported `MappedTrade` records carry `tradingMode: .crossMargin` or `.isolatedMargin`.
- Preview and noop variants return empty results.
- The service handles Binance's `fromId` pagination for margin trades identically to
  spot: fetch in batches of 1000, loop until fewer returned, update sync metadata.

## Planned Implementation Tasks

- [ ] test: `MarginTradeImportService.sync` calls correct margin endpoint per mode
- [ ] test: pagination works (batches of 1000, loops until exhausted)
- [ ] test: rate-limit retry triggers on HTTP 429
- [ ] test: isolated margin uses `isolatedMarginKey` in SyncMetadata
- [ ] test: cross margin uses `"cross"` sentinel in SyncMetadata
- [ ] test: imported trades carry `tradingMode: .crossMargin` / `.isolatedMargin`
- [ ] test: partial failure of one isolated symbol doesn't block others
- [ ] test: preview/noop return empty results
- [ ] feat: `MarginTradeImportService` struct with `sync` closure
- [ ] feat: `live()` implementation calling `fetchMarginMyTrades` with correct params
- [ ] feat: `preview` / `noop` variants

## Check for Understanding

1. How does `MarginTradeImportService` handle the difference between cross-margin's
    single global sync cursor and isolated-margin's per-isolated-symbol cursors?
2. Why does this advance reuse `MappedTrade` and `SyncUpdate` from the spot import
    service rather than creating new types?
3. How does the `isIsolated` flag propagate from the `TradingMode` parameter to the
    Binance API request?

## Risk + Rollback

- Risk: additive new service. No existing code path changes.
- Rollback: revert commits. No migration needed.

## Evidence

- [ ] tidy:preparatory (reuses existing MappedTrade, SyncUpdate, TradeImportResult)
- [ ] tdd:red-green
- [ ] tests:unit (MarginTradeImportServiceTests — target 8 tests)

## Changes Made

### 2026-08-08: Add MarginTradeImportService (cross + isolated margin sync, pagination, rate-limit retry)

**feat**

- `EasyCrypto/Core/Models/MarginBalance.swift`: Modified
- `EasyCrypto/Core/Services/BinanceAPIClient.swift`: Modified
- `EasyCryptoTests/Core/Models/MarginBalanceTests.swift`: Modified
- `EasyCryptoTests/Core/Models/TradingModeTests.swift`: Modified
- `EasyCryptoTests/Core/Services/BinanceMarginAPITests.swift`: Modified
- `EasyCryptoTests/Core/Services/PriceServiceTests.swift`: Modified
- `EasyCryptoTests/Core/Services/TradeImportServiceTests.swift`: Modified
- `arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-005.md`: Modified
- `arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-006.md`: Modified
- `arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-007.md`: Modified
- `arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-008.md`: Modified
- `docs/1.project-overview.md`: Modified
- `EasyCrypto/Core/Services/MarginTradeImportService.swift`: Added
- `EasyCryptoTests/Core/Services/MarginTradeImportServiceTests.swift`: Added

