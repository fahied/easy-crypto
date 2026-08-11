---
advance:
  id: "ADV-PORTFOLIO-005"
  title: "Portfolio tab mode-segmented UI — Overview / Spot / Cross Margin / Isolated Margin"
  system: "easycrypto-core"
  primary_component: "portfolio"
  components: ["portfolio"]
  started_at: "2026-08-11T00:00:00Z"
  implementation_completed_at: "2026-08-11T00:00:00Z"
  review_time_estimate_minutes: 30
  review_time_actual_minutes: 15
  pr_links: []
  reviewability_score: 25
  risk_flags: []
  evidence: []
  model_usage: []
  status: complete
---

## Objective

Replace the Portfolio tab's flat layout (all-mode summary cards + mode breakdown rows)
with a Binance-style segmented control: **Overview** (aggregate), **Spot** (spot-only),
**Cross Margin** (cross-margin-only), **Isolated Margin** (isolated-margin-only).

Each segment shows the same set of metric cards but filtered to that mode. Overview
aggregates across all three modes. The tab remains **read-only** — no trading, no
modification of positions.

Follows:
- ADV-PORTFOLIO-003 (per-mode summary aggregation already computed)
- ADV-PORTFOLIO-002 (unified holdings across spot + margin modes)

## Behavioral Change

After this advance:

- Portfolio tab top bar has a **segmented picker**: Overview | Spot | Cross Margin | Isolated Margin
- **Overview** — metric cards show aggregate totals across all modes (Total Invested,
  Current Value, Total P&L, Unrealized P&L, Realized P&L, holdings count)
- **Spot** — same metric cards computed from spot-only holdings
- **Cross Margin** — same metric cards computed from cross-margin holdings only
- **Isolated Margin** — same metric cards computed from isolated-margin holdings only
- Switching segments **filters** the displayed summary — no re-fetch required
- Refresh button still triggers a full sync (spot + both margin modes in parallel)
- The mode breakdown card (previously showing all three modes) is removed — its
  information is now visible by switching to each segment
- Read-only: no buy/sell/transfer actions anywhere in the Portfolio tab

## Design Notes

- **Segmented Picker**: Uses the existing `Picker(.segmented)` style from SwiftUI.
  Each tag maps to a `PortfolioTab` enum case. Binding updates the state and triggers
  a lightweight recompute of the summary for that mode.
- **Processor does not need to change**: `computeSummary()` already builds per-mode
  `PortfolioSummary` objects (spot, crossMargin, isolatedMargin). The view selects
  which summary to display based on the active tab. A new computed property
  `summary(for:)` returns the appropriate `PortfolioSummary`.
- **Single source of truth**: The full summary (all modes) is computed once during
  `refresh()` and stored in `state.summary`. The view derives per-mode summaries from
  the same object — no redundant computation.
- **Mode breakdown card removed**: The `ModeBreakdownRow` rows are removed. Their
  data is accessible via the segmented control.
- **No data model changes**: `PortfolioSummary` already has per-mode `ModeSummary`
  fields. No schema changes required.
- **No persistence changes**: All existing SwiftData models remain unchanged.
- **No Holdings tab changes**: The Holdings tab (separate feature) is unaffected.

## Component Impact

- **portfolio** (`EasyCrypto/Features/Portfolio/`):
  - `PortfolioView.swift` — replace summary grid + mode breakdown with segmented picker
    + single summary grid that updates based on selected tab
  - `PortfolioState.swift` — add `selectedTab: PortfolioTab` field
  - `PortfolioProcessor.swift` — add `summary(for:)` computed property that returns
    the appropriate `PortfolioSummary` for a given `PortfolioTab`
  - `PortfolioIntent.swift` — add `selectTab(PortfolioTab)` case (or handle directly
    in view binding)

- **core-models** (`EasyCrypto/Core/Models/`):
  - No changes needed — `PortfolioSummary.ModeSummary` already exists

## Out of Scope

- Holdings list in Portfolio tab (removed in ADV-PORTFOLIO-004)
- Per-asset detail from Portfolio (Holdings tab is the place)
- Mode-specific P&L charts or trends
- Portfolio allocation pie chart by mode
- Export per-mode data to CSV
- Trading actions (buy/sell/transfer) — this remains read-only
- Editing holdings or adjusting quantities

## Planned Implementation Tasks

- [x] test: `summary(for:)` returns correct summary for each tab
- [x] test: switching tab does not trigger refresh or data reload
- [x] test: existing `refresh()` and `loadPersistedData()` still produce correct summary
- [x] implement: add `PortfolioTab` enum (overview, spot, crossMargin, isolatedMargin)
- [x] implement: add `selectedTab` to `PortfolioState`
- [x] implement: add `summary(for:)` to `PortfolioProcessor`
- [x] implement: replace `summaryGrid` + `modeBreakdown` in `PortfolioView` with segmented picker + tab-filtered summary grid
- [x] implement: update previews for each tab state
- [x] tidy: remove `modeBreakdown` view from `PortfolioView`
- [x] verify: existing PortfolioProcessor tests still pass

## Risk + Rollback

- Risk: segmented picker adds view state that must stay in sync with processor data.
  Low risk — the binding is straightforward and the summary is immutable once computed.
- Rollback: revert commits. No migration needed. The old flat layout can be restored
  by reverting `PortfolioView` changes.

## Changes Made

- **PortfolioState.swift**: Added `PortfolioTab` enum (String raw values: overview, spot, crossMargin, isolatedMargin) and `selectedTab: PortfolioTab = .overview` field to `PortfolioState`.
- **PortfolioIntent.swift**: Added `selectTab(PortfolioTab)` case to `PortfolioIntent`. Moved `PortfolioTab` enum to `PortfolioState.swift` to avoid cross-file type ordering issues.
- **PortfolioProcessor.swift**: Added `handle(.selectTab)` case (no-op, tab switching handled in view binding). Added `summary(for:)` computed property that returns a flat `PortfolioSummary` derived from the appropriate per-mode `ModeSummary`.
- **PortfolioSummary.swift**: Added `init(from mode: ModeSummary)` convenience initializer that creates a flat `PortfolioSummary` from a single `ModeSummary`, with all per-mode fields zeroed.
- **PortfolioView.swift**: Replaced `modeBreakdown` + flat summary grid with `modeSegmentedPicker` (segmented Picker bound to `selectedTab`) + single `summaryGrid` that reads from `processor.summary(for: state.selectedTab)`. Removed dead `ModeBreakdownRow` struct. Updated empty state check to use `processor.summary(for: state.selectedTab).isEmpty`. Updated 4 previews to use `PreviewSampleData.samplePortfolioSummary` with per-tab `selectedTab` values; added Empty, Loading, and Error state previews.
- **PreviewSampleData.swift**: Added `samplePortfolioSummary` static property with realistic per-mode breakdown (spot: $51.25k/$67.25k, crossMargin: $25k/$31k, isolatedMargin: $15k/$18k).

## Check for Understanding

1. How does `summary(for:)` avoid recomputing the full summary when the user switches
   tabs, and why is it safe to derive per-mode summaries from the aggregate?
2. Why does the segmented picker use a binding to `PortfolioState.selectedTab` rather
   than triggering a new `PortfolioIntent`?
3. How does removing the mode breakdown card change the information architecture, and
   what must the Holdings tab continue to provide to compensate?
