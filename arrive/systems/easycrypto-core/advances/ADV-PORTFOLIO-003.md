---
advance:
  id: "ADV-PORTFOLIO-003"
  title: "Portfolio summary metrics aggregate across Spot and Margin modes"
  system: "easycrypto-core"
  primary_component: "portfolio"
  components: ["portfolio", "core-models", "core-services"]
  started_at: "2026-08-10"
  implementation_completed_at: ~
  review_time_estimate_minutes: 20
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 20
  risk_flags: []
  evidence: []
  model_usage: []
  status: planned
---

## Objective

The Portfolio tab shows both summary metric cards (Total Invested, Current Value,
Total P&L, Unrealized P&L, Realized P&L) **and** a holdings list at the bottom.
The holdings list duplicates what the dedicated Holdings tab already provides.

After this advance, the Portfolio tab shows **only summary metric cards** — the
holdings list is removed (ADV-PORTFOLIO-004). The summary metrics always aggregate
across all trading modes (spot + cross-margin + isolated-margin), giving a complete
portfolio picture at a glance. The dedicated Holdings tab remains the place for
per-asset detail, filterable by trading mode.

## Behavioral Change

After this advance:

- Portfolio tab shows **summary metric cards** that always aggregate across all
  trading modes (spot + cross-margin + isolated-margin).
- No holdings list in the Portfolio tab — that moves to the dedicated Holdings tab.
- Summary cards show: Total Invested, Current Value, Total P&L, Unrealized P&L,
  Realized P&L — all computed from the combined holdings set.
- A combined value (e.g., "7 assets") reflects the total count across all modes.
- A small breakdown by mode is shown within or beneath each card so users can see
  the per-mode contribution (e.g., "Spot: $50k / Margin: $30k").
- Spot-only users see no behavior change — the aggregate equals spot-only values.
- Refresh button fetches both spot and margin data in parallel for efficiency.
- No mode picker needed on the Portfolio tab — it always shows the full picture.

## Design Notes

- **Combined refresh**: Instead of a single mode refresh, the processor fetches spot
  and margin data in parallel using `async let`. This avoids sequential API calls.
- **Aggregate summary**: `PortfolioSummary` is computed from the combined holdings
  set (all modes merged). The total holdings count reflects the aggregate across all
  modes.
- **Per-mode breakdown**: Each summary card shows the total value plus a small
  breakdown by mode (e.g., "Spot: $50k · Margin: $30k") so users understand where
  their value comes from without switching tabs.
- **No mode picker on Portfolio**: The Portfolio tab always shows the full picture.
  The mode picker stays on the Holdings tab for per-asset detail.
- **Holdings list removed from Portfolio**: The bottom holdings list is removed from
  this tab entirely. The Holdings tab (ADV-PORTFOLIO-004) is the single source for
  per-asset detail.
- **No data model changes**: All required fields already exist on `Holding`,
  `PortfolioSummary`, and `PortfolioState`. The per-mode breakdown is computed in
  the summary layer.

## Component Impact

- **portfolio** (`EasyCrypto/Features/Portfolio/`):
  - `PortfolioProcessor.swift` — `refresh()` fetches spot + margin in parallel;
    summary always reflects combined holdings from all modes
  - `PortfolioView.swift` — remove holdings list; keep metric cards with per-mode
    breakdown; no mode picker needed
  - `PortfolioState.swift` — may simplify if `selectedTradingMode` was only used
    for the holdings list filter

- **core-models** (`EasyCrypto/Core/Models/`):
  - `PortfolioSummary` — add optional per-mode breakdown fields, or compute inline
  - No changes to `TradingMode` enum

## Out of Scope

- Holdings list (moved to Holdings tab)
- Mode picker on Portfolio tab (not needed — always shows all)
- Per-asset drill-down from Portfolio
- Portfolio allocation pie chart by mode
- Mode-specific P&L trends
- Export combined portfolio to CSV
- Holdings list removal (ADV-PORTFOLIO-004)

## Planned Implementation Tasks

- [ ] test: `refresh()` fetches spot and margin in parallel
- [ ] test: summary metrics reflect combined holdings across all modes
- [ ] test: per-mode breakdown splits values correctly (spot vs cross vs isolated)
- [ ] test: existing PortfolioProcessor tests still pass
- [ ] implement: `PortfolioProcessor.refresh()` — parallel spot + margin fetch
- [ ] implement: aggregate summary from combined holdings
- [ ] implement: per-mode breakdown in `PortfolioSummary`
- [ ] implement: remove holdings list from `PortfolioView`
- [ ] implement: simplify `PortfolioView` to show only metric cards
- [ ] implement: remove mode picker from Portfolio (if present)
- [ ] tidy: simplify `PortfolioState` if `selectedTradingMode` is no longer needed

## Risk + Rollback

- Risk: changes refresh flow to parallel fetch. Sequential fallback available if
  parallel causes issues with rate limits.
- Rollback: revert commits. No migration needed.

## Changes Made

*(filled during implementation)*

## Check for Understanding

1. How does the parallel spot + margin fetch avoid sequential API calls, and what
   happens if one of the two fetches fails?
2. Why does the summary aggregate across all modes rather than showing only the
   selected mode?
3. How does the per-mode breakdown help users understand their portfolio composition
   without needing a mode picker on this tab?
