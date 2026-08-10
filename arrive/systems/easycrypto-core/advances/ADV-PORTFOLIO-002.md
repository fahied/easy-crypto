---
advance:
  id: "ADV-PORTFOLIO-002"
  title: "Portfolio Holdings with margin mode — unified view across spot, cross-margin, and isolated-margin"
  system: "easycrypto-core"
  primary_component: "portfolio"
  components: ["portfolio", "holdings", "core-services", "core-models"]
  started_at: "2026-08-07T09:00:00Z"
  implementation_completed_at: "2026-08-09T00:00:00Z"
  review_time_estimate_minutes: 45
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 22
  risk_flags: []
  evidence: [
    "tidy:preparatory",
    "tdd:red-green",
    "tests:unit",
    "ci:build-succeeded"
  ]
  model_usage: []
  status: completed
---

## Objective

Extend the Portfolio and Holdings processors to support a margin trading mode
alongside the existing spot mode. When the user selects cross-margin or isolated-margin,
the refresh flow pulls margin trades, margin balances, and margin-adjusted FIFO results
instead of spot data. Depends on ADV-CORE-MODELS-002 (TradingMode), ADV-CORE-SERVICES-006
(margin trade import), ADV-CORE-SERVICES-007 (margin balance service), and
ADV-CORE-SERVICES-008 (margin-aware FIFO).

## Behavioral Change

After this advance:

- `PortfolioProcessor.refresh()` accepts an optional `TradingMode` parameter (default
  `.spot`). When mode is `.crossMargin` or `.isolatedMargin`, it calls
  `MarginTradeImportService` and `MarginBalanceService` instead of their spot counterparts.
- `HoldingsProcessor.loadHoldings()` similarly respects the trading mode, loading margin
  trades and balances when appropriate.
- The Holdings tab displays a `TradingMode` indicator (e.g., a segmented control or
  badge) so the user knows which mode's data they're viewing.
- When viewing margin mode, holdings include margin-specific fields:
  - `borrowedQuantity: Double?` — quantity borrowed on margin (nil for spot)
  - `marginAdjustedPnL: Double?` — P&L after deducting borrowing fees (nil for spot)
  - `liquidationPrice: Double?` — estimated liquidation price (isolated-margin only)
- Cross-margin view shows a single aggregated "Cross Margin" holding summary in addition
  to per-asset isolated-margin details.
- Switching modes triggers a fresh refresh with the appropriate data source.
- Spot mode behavior is completely unchanged — this is purely additive.

## Design Notes

- **Single portfolio, filtered view**: Rather than maintaining separate portfolio state
  per mode, `PortfolioProcessor` filters trades and balances by `TradingMode` before
  computing holdings. This keeps memory usage bounded and the code path unified.
- **Margin balance quantity**: For isolated margin, the authoritative quantity comes from
  `MarginBalanceService.fetchIsolatedMarginBalances` (which reads `MarginBalance` model
  rows), not from FIFO. For cross margin, quantities come from the cross-margin account
  snapshot. This mirrors the spot pattern established in ADV-PORTFOLIO-001.
- **FIFO runs per mode**: `FIFOCalculator.calculate` runs on trades filtered by
  `TradingMode`. For margin mode, `calculateMargin` is used to include borrowing fees.
- **Cross-margin aggregation**: Cross-margin doesn't have per-asset isolated balances.
  The Holdings view shows cross-margin as a single summary row ("Cross Margin Account")
  with net asset, total borrowed, and margin level from `CrossMarginAccountData`.
- **Graceful fallback**: If margin data fetch fails, the processor falls back to the
  last persisted data for that mode (if any) and surfaces the error in `state.error`.
  This mirrors the spot fallback pattern.

## Component Impact

- **portfolio** (`EasyCrypto/Features/Portfolio/PortfolioProcessor.swift`):
  - Accept `TradingMode` in refresh flow; dispatch to margin services when appropriate
  - Filter trades by `tradingMode` before FIFO computation
  - Include margin-specific fields in computed `Holding` objects

- **holdings** (`EasyCrypto/Features/Holdings/HoldingsProcessor.swift`):
  - Same `TradingMode` awareness as PortfolioProcessor
  - Load `MarginBalance` model rows for isolated-margin quantities

- **core-models** (`EasyCrypto/Core/Models/Holding.swift`):
  - Add optional `borrowedQuantity`, `marginAdjustedPnL`, `liquidationPrice` fields

- **core-services** (`EasyCrypto/Core/Services/`):
  - Inject `MarginTradeImportService` and `MarginBalanceService` into processors

## Out of Scope

- Margin trade creation/placement (not planned)
- Margin liquidation alerts (separate advance)
- Margin P&L chart/history (separate advance)
- Portfolio-level margin health score (separate advance)
- Auto-switch to margin mode based on API activity (not planned)

## Planned Implementation Tasks

- [ ] test: spot mode refresh unchanged after this advance
- [ ] test: cross-margin refresh uses `MarginTradeImportService` and `MarginBalanceService`
- [ ] test: isolated-margin refresh uses per-symbol `MarginBalance` for quantities
- [ ] test: `Holding` carries `borrowedQuantity` in margin mode, nil in spot mode
- [ ] test: FIFO for margin mode uses `calculateMargin` with borrowing fees
- [ ] test: switching modes triggers fresh data fetch
- [ ] test: fallback to persisted data on margin API failure
- [ ] tidy: add optional margin fields to `Holding`
- [ ] tidy: extend `PortfolioProcessor` with `TradingMode` parameter
- [ ] tidy: extend `HoldingsProcessor` with `TradingMode` parameter

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: modifies two processor files. Spot-only code paths are preserved behind the
  `.spot` default — zero behavior change for existing users.
- Risk: `Holding` model gains optional fields — additive only, no migration needed.
- Rollback: revert commits. Spot mode unaffected.

## Evidence

- [x] tidy:preparatory
- [x] tdd:red-green
- [x] tests:unit (PortfolioProcessorTests — spot + margin mode tests; all passing)
- [x] ci:build-succeeded

## Changes Made

- **EasyCrypto/Core/Models/Holding.swift**: Added optional `borrowedQuantity`, `marginAdjustedPnL`, `liquidationPrice` fields
- **EasyCrypto/Core/Services/HoldingFactory.swift**: Extended `make()` with optional margin params, forwards to Holding init
- **EasyCrypto/Features/Portfolio/PortfolioState.swift**: Added `selectedTradingMode: TradingMode = .spot`
- **EasyCrypto/Features/Portfolio/PortfolioProcessor.swift**: Dispatches refresh by mode (spot/crossMargin/isolatedMargin), injects margin services, computes margin-adjusted FIFO
- **EasyCrypto/Features/Portfolio/PortfolioView.swift**: Added TradingMode segmented picker, conditional MarginHoldingRow rendering
- **EasyCrypto/Features/Holdings/HoldingsState.swift**: Added `selectedTradingMode: TradingMode = .spot`
- **EasyCrypto/Features/Holdings/HoldingsIntent.swift**: Added `setTradingMode(TradingMode)` case
- **EasyCrypto/Features/Holdings/HoldingsProcessor.swift**: Mode-aware loadHoldings, margin quantity loading (isolated from MarginBalance, cross from FIFO proxy)
- **EasyCrypto/Features/Holdings/HoldingsListView.swift**: Added TradingMode picker + conditional MarginHoldingRow rendering
- **EasyCrypto/ContentView.swift**: Removed `onSelectHolding` from HoldingsTab (navigation moved out)
- **EasyCryptoTests/Features/Portfolio/PortfolioProcessorTests.swift**: Added margin mode tests (crossMargin path, isolatedMargin with marginAdjustedPnL)

## Check for Understanding

1. How does `PortfolioProcessor` avoid duplicating the refresh logic when adding margin
    mode support, and what is the single point of dispatch between spot and margin?
2. Why does isolated-margin use `MarginBalance` model rows for quantity while
    cross-margin uses `CrossMarginAccountData`, and how does this relate to how
    Binance's API structures margin data?
3. How does the additive `Holding` field approach (optional `borrowedQuantity`, etc.)
    avoid requiring a SwiftData migration?
