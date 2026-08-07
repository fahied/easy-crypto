---
advance:
  id: "ADV-CORE-SERVICES-006"
  title: "Margin trade import service — cross-margin and isolated-margin incremental sync"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "core-models"]
  started_at: "2026-08-07T09:00:00Z"
  implementation_completed_at: ~
  review_time_estimate_minutes: 30
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  model_usage: []
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

## Design Notes

- **Reuse over duplicate**: `MarginTradeImportService` reuses `MappedTrade`, `SyncUpdate`,
  and `TradeImportResult` from `TradeImportService` — no new import types needed.
- **Isolated margin keying**: Isolated-margin trades in Binance's API are scoped by an
  `isolatedMarginKey` (e.g., `BTCUSDT`), not by symbol alone. The sync metadata for
  isolated margin uses `isolatedMarginKey` as the key, while cross-margin uses a
  single `"cross"` key. This maps cleanly to the existing `SyncMetadata` model via
  the composite `(symbol, tradingMode)` key — for isolated, `symbol` holds the
  `isolatedMarginKey`; for cross, it's a sentinel.
- **Rate limits**: Margin endpoints have separate weight limits (typically 50 per minute).
  The same retry strategy (3 retries, exponential backoff) applies.

## Component Impact

- **core-services** (`EasyCrypto/Core/Services/`):
  - New `MarginTradeImportService.swift` — struct-with-closures, mirrors `TradeImportService`
    pattern but calls margin endpoints

## Out of Scope

- Isolated-margin symbol discovery (can reuse `MarginBalance` endpoint; no new discovery
  needed — same symbols as spot)
- Margin trade deletion/cancellation (read-only)
- Margin P&L calculation (ADV-CORE-SERVICES-007)
- Margin UI (ADV-TRADE-HISTORY-001)

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

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: additive new service. No existing code path changes.
- Rollback: revert commits. No migration needed.

## Evidence

- [ ] tidy:preparatory (reuses existing MappedTrade, SyncUpdate, TradeImportResult)
- [ ] tdd:red-green
- [ ] tests:unit (MarginTradeImportServiceTests — target 8 tests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-SERVICES-006 --status passed`

## Changes Made

*(populated during implementation)*

## Check for Understanding

1. How does `MarginTradeImportService` handle the difference between cross-margin's
    single global sync cursor and isolated-margin's per-isolated-symbol cursors?
2. Why does this advance reuse `MappedTrade` and `SyncUpdate` from the spot import
    service rather than creating new types?
3. How does the `isIsolated` flag propagate from the `TradingMode` parameter to the
    Binance API request?
