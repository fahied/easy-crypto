---
advance:
  id: "ADV-AI-INSIGHTS-006"
  title: "Profit breakdown screen: per-asset P&L and average profit per trade in Insights"
  system: "easycrypto-core"
  primary_component: "ai-insights"
  components: ["ai-insights"]
  started_at: "2026-07-17T00:00:00Z"
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

Add a **profit breakdown summary** to the Insights tab that surfaces two key
metrics — **profit per asset** (per-symbol realized P&L) and **average profit
per trade** — in a dedicated card positioned **above the Analyze button**. The
data comes from the existing `TradeSummary` / `SymbolSummary` models, so no new
data layer is required.

## Behavioral Change

After this advance:
- The **Insights** tab shows a new summary card (above the Analyze button) with:
  - **Per-asset profit**: a compact list of the user's traded symbols, each with
    its realized P&L (green for profit, red for loss), sorted by P&L descending.
  - **Average profit per trade**: total realized P&L divided by sell count,
    displayed as a single metric in the same card.
- The card uses existing design-system components (`GlassCard`, `MetricCard`,
  `PnLLabel`) and reuses `TradeSummary` / `SymbolSummary` — no new models or
  services.
- The card is visible whenever the insights engine is `.ready`; it shows a
  "No trades yet" placeholder when there are no sells.
- The card does **not** affect the Analyze flow, the chat flow, or any existing
  behavior — it is additive.

## Data Source

- `TradeSummary.totalRealizedPnL` and `TradeSummary.topSymbols` (each
  `SymbolSummary` carries `realizedPnL`) are already computed by
  `TradePatternSummarizer` (ADV-AI-INSIGHTS-001). No new calculation needed.
- Average profit per trade = `totalRealizedPnL / sellCount` (guarded for zero
  division). This is a view-level derivation, not a stored field.

## Component Impact

- **ai-insights** (`EasyCrypto/Features/Insights/**`):
  - New `ProfitBreakdownView` — stateless view that takes a `TradeSummary` and
    renders the per-asset list + average metric using design-system components.
  - `InsightsView` — insert the new card above the Analyze button in
    `headerCard` (or as a separate section between the insight list and the
    buttons). Wire it to `state.tradeSummary` (already in `InsightsState`).

## Out of Scope

- Detailed per-trade breakdown or drill-down into individual trades.
- Charts or sparklines (future enhancement).
- Changing the `TradeSummary` model or `TradePatternSummarizer`.

## Planned Implementation Tasks

- [ ] branch: create/confirm feature branch for this advance
- [ ] test (ai-insights): `ProfitBreakdownView` renders per-asset rows sorted by
      P&L descending with correct sign coloring
- [ ] test (ai-insights): `ProfitBreakdownView` shows "No trades yet" when
      `topSymbols` is empty
- [ ] test (ai-insights): average profit per trade is computed correctly
      (totalRealizedPnL / sellCount, zero-division guard)
- [ ] feat (ai-insights): `ProfitBreakdownView` using existing design-system
      components, wired into `InsightsView` above the Analyze button
- [ ] feat (ai-insights): `ProfitBreakdownView` preview in `InsightsView`

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: none — additive UI change, no new data path, no behavior change to
  existing flows. Existing `TradeSummary` is already bounded and deterministic.
- Rollback: revert the advance's commits. No migration or data change needed.

## Evidence

- [ ] tdd:red-green
- [ ] tests:unit

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-AI-INSIGHTS-006 --status passed`

## Changes Made

### <DATE> - <commit-prefix>: <summary>
- <file>: <what changed>

## Check for Understanding

1. Where does the profit-per-asset data come from, and why doesn't this advance
   need a new model or service?
2. How is average profit per trade computed, and what guards prevent a
   divide-by-zero when there are no sells?
3. Why is this advance scoped to a UI-only addition, and what existing flows
   are explicitly left untouched?
