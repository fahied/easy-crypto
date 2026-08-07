---
advance:
  id: "ADV-TRADE-HISTORY-001"
  title: "Margin trade history — filterable by trading mode with borrowing fee display"
  system: "easycrypto-core"
  primary_component: "trade-history"
  components: ["trade-history", "core-services", "core-models", "portfolio"]
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

Extend `TradeHistoryProcessor` and `TradeHistoryView` to display trades filtered by
`TradingMode` (spot, cross-margin, isolated-margin), with margin-specific columns
showing borrowing fees and margin-adjusted P&L per trade. Depends on ADV-CORE-MODELS-002
(TradingMode), ADV-CORE-SERVICES-006 (margin trade import), and ADV-CORE-SERVICES-008
(margin-aware FIFO).

## Behavioral Change

After this advance:

- `TradeHistoryProcessor` accepts an optional `TradingMode` parameter (default `.spot`).
  When set, `fetchAllTrades()` filters by `tradingMode` using a SwiftData predicate.
- `TradeHistoryView` gains a `TradingMode` segmented control (Spot / Cross-Margin /
  Isolated-Margin) at the top, defaulting to Spot.
- Each trade row in the history shows a mode badge (colored dot or tag):
  - Blue for spot, orange for cross-margin, purple for isolated-margin
- Margin trade rows show an additional "Fee" column displaying the borrowing fee
  portion of the commission (if applicable).
- The "P&L" column for margin trades shows margin-adjusted P&L (after borrowing fees)
  rather than raw realized P&L.
- The coin filter dropdown continues to work within the selected mode.
- Switching modes clears the current filter and reloads from the appropriate trade set.
- Spot-only users see no UI change — the segmented control is always present but
  defaults to Spot.

## Design Notes

- **Predicate filtering**: SwiftData's `#Predicate<Trade>` supports equality filtering
  on the `tradingMode` field (introduced in ADV-CORE-MODELS-002). The processor builds
  a predicate like `#Predicate<Trade> { $0.tradingMode == .crossMargin }`.
- **Borrowing fee display**: The `Trade` model doesn't store borrowing fees directly
  (they're part of the commission in the Binance API). The processor enriches each
  trade row with a computed `borrowingFee` by looking up the fee from the
  `MarginFIFOResult` for the asset, proportionally distributed across sells.
- **Reuse existing aggregation**: `buildDetails` already computes `SaleBreakdown`
  per trade via `saleBreakdowns`. For margin mode, it calls `saleBreakdowns` with
  the borrowing fee per unit, producing margin-adjusted breakdowns.
- **DayTradeDetail extension**: Add optional `borrowingFee: Double` and
  `marginAdjustedPnL: Double?` fields to `DayTradeDetail` so the view can display them.
- **No data migration**: All new fields are optional on existing types or new
  computed properties.

## Component Impact

- **trade-history** (`EasyCrypto/Features/TradeHistory/`):
  - `TradeHistoryProcessor.swift` — add `TradingMode` filter, margin-aware breakdowns
  - `TradeHistoryView.swift` — add segmented control, mode badge, fee column
  - `TradeHistoryState.swift` — add `selectedTradingMode` field
  - `DayDetailView.swift` — show margin details when applicable

- **core-models** (`EasyCrypto/Core/Models/DayTradeDetail` or computed inline):
  - Add optional `borrowingFee` and `marginAdjustedPnL` to the detail type

## Out of Scope

- Margin trade deletion/cancellation
- Margin liquidation history
- Export margin trades to CSV
- Margin trade search/filter beyond coin + mode

## Planned Implementation Tasks

- [ ] test: spot-only filter returns only spot trades
- [ ] test: cross-margin filter returns only cross-margin trades
- [ ] test: isolated-margin filter returns only isolated-margin trades
- [ ] test: mode badge appears with correct color per TradingMode
- [ ] test: borrowing fee column populated for margin trades
- [ ] test: switching modes clears and reloads
- [ ] tidy: add `selectedTradingMode` to `TradeHistoryState`
- [ ] tidy: filter `fetchAllTrades` by `tradingMode` predicate
- [ ] tidy: add mode badge, fee column to `TradeHistoryView`
- [ ] tidy: extend `DayTradeDetail` with margin-specific optional fields

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: modifies trade history UI and processor. Spot-only behavior is preserved by
  the `.spot` default.
- Rollback: revert commits. No migration needed.

## Evidence

- [ ] tidy:preparatory
- [ ] tdd:red-green
- [ ] tests:unit (MarginTradeHistoryTests — target 6 tests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-TRADE-HISTORY-001 --status passed`

## Changes Made

*(populated during implementation)*

## Check for Understanding

1. How does the `TradingMode` filter in `TradeHistoryProcessor` use SwiftData predicates,
    and why is this preferable to fetching all trades and filtering in memory?
2. Why does `DayTradeDetail` need new optional fields for margin data instead of
    reusing existing fields?
3. How does the segmented control in `TradeHistoryView` interact with the existing
    coin filter, and what happens to both when the mode changes?
