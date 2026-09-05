---
advance:
  id: "ADV-PORTFOLIO-006"
  title: "Invested Assets screen — add P&L label below each row's current value"
  system: "easycrypto-core"
  primary_component: "portfolio"
  components: ["portfolio", "design-system"]
  started_at: "2026-08-31T00:00:00Z"
  implementation_completed_at: "2026-08-31T00:00:00Z"
  review_time_estimate_minutes: 15
  review_time_actual_minutes: 10
  pr_links: []
  reviewability_score: 10
  risk_flags: []
  evidence: ["tdd:red-green", "tests:unit"]
  model_usage: []
  status: complete
---

## Objective

Add a P&L label below each asset row's "Current Value" on the Invested Assets screen.
The label shows `+$X,XXX.XX (XX.XX%)` or `-$X,XXX.XX (-XX.XX%)` with profit/loss color
coding, so users can see at a glance which holdings are winning without tapping into the
Holdings tab.

This is a UI-only enhancement. The data needed (`amountInvestedUSDT`, `currentValueUSDT`)
is already present on `InvestedAssetRow`. The total summary header also gains a matching
P&L row.

## Behavioral Change

After this advance:

- Each asset row shows three lines: invested (muted), current value (bold), P&L (colored)
  - Profit: green P&L with arrow-up icon
  - Loss: red P&L with arrow-down icon
  - Breakeven: neutral/muted
- The total summary header gains a "P&L" line showing aggregate profit or loss with percentage
- The existing invested and current-value columns remain unchanged
- Sorting order is unchanged (assets sorted by invested descending)

## Design Notes

- Reuse the existing `PnLLabel` design-system view — it already implements profit/loss
  color coding, arrow icons, and the `signedUsdtFormatted` / `percentFormatted` formatting.
- The per-row P&L is derived: `(currentValueUSDT - amountInvestedUSDT)` for the absolute
  value, `(pnL / amountInvestedUSDT) * 100` for the percentage.
- The aggregate P&L is the sum of all per-row P&L values, computed at the same point the
  totals are already computed in `PortfolioProcessor`.
- No TradingMode badge change — it stays above the value lines in the same column.
- Layout: the right-side VStack gains one more element. The `TradingModeBadge` stays left;
  the value/P&L stack stays right.

## Component Impact

- **portfolio** (`EasyCrypto/Features/Portfolio/`):
  - `PortfolioState.swift` — add `unrealizedPnL` and `unrealizedPnLPercent` to `InvestedAssetRow`
  - `PortfolioProcessor.swift` — compute and pass P&L fields when building `InvestedAssetRow` list; compute aggregate totals
  - `InvestedAssetsView.swift` — add `pnlLabel` to the row's right-side stack; add P&L to the total summary header

- **design-system** (`EasyCrypto/DesignSystem/`):
  - No changes needed — `PnLLabel` is already available

- **core-models** (`EasyCrypto/Core/Models/`):
  - No changes needed

## Out of Scope

- Sorting by P&L (existing sort is by invested)
- Per-mode breakdown in Invested Assets
- Tapping a row to navigate to coin detail
- Realized P&L display (only unrealized is shown)
- Percentage-of-portfolio allocation
- Charts or sparklines

## Planned Implementation Tasks

- [ ] test: `InvestedAssetRow` computes correct `unrealizedPnL` and `unrealizedPnLPercent`
- [ ] test: total P&L is the sum of all row P&L values
- [ ] implement: add `unrealizedPnL` and `unrealizedPnLPercent` to `InvestedAssetRow`
- [ ] implement: compute P&L fields in `handleShowInvestedAssets()`
- [ ] implement: add `PnLLabel` below current value in `InvestedAssetRowView`
- [ ] implement: add P&L to total summary header in `InvestedAssetsView`
- [ ] implement: update previews to show profit, loss, and mixed scenarios
- [ ] verify: build passes

## Risk + Rollback

- Risk: low. The P&L values are derived from existing fields on `InvestedAssetRow`. No
  new data fetching, no schema changes, no API calls.
- Rollback: revert the three file changes. `InvestedAssetRow` fields are additive — old
  callers that don't set them will see zero P&L (safe fallback).

## Changes Made

- **PortfolioState.swift**: Added `unrealizedPnL` and `unrealizedPnLPercent` fields to `InvestedAssetRow` (with defaults for backward compat). Added `totalPnL` and `totalPnLPercent` fields to `InvestedAssetsDestination`.
- **PortfolioProcessor.swift**: In `handleShowInvestedAssets()`, computed per-row `pnl = currentValue - invested` and `pnlPercent = pnl/invested * 100`; computed aggregate `totalPnL` and `totalPnLPercent`; passed all four values into `InvestedAssetRow` and `InvestedAssetsDestination`.
- **InvestedAssetsView.swift**: Added `PnLLabel` (reused from design system) below each row's current value, guarded on `amountInvestedUSDT > 0`. Added a P&L row to the total summary header, right-aligned below current value. Updated all previews to include P&L data.
- **PortfolioProcessorTests.swift**: Added two tests: `rowsContainUnrealizedPnL` (per-row P&L values for profit and loss scenarios) and `totalPnLIsSumOfRows` (aggregate P&L verification).

## Check for Understanding

1. Why is it safe to compute per-row P&L as `(currentValue - invested) / invested` rather
   than going back to the FIFO calculator?
2. How does the existing `PnLLabel` view ensure consistent color coding with the Holdings
   tab's profit chips?
