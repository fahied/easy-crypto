---
advance:
  id: "ADV-AI-INSIGHTS-006"
  title: "Profit breakdown card at top of Insights tab with auto-refresh on tab open"
  system: "easycrypto-core"
  primary_component: "ai-insights"
  components: ["ai-insights"]
  started_at: "2026-07-17T00:00:00Z"
  implementation_completed_at: "2026-07-18T22:57:00Z"
  review_time_estimate_minutes: 30
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  model_usage: []
  status: complete
---

## Objective

Add a **profit breakdown summary** to the Insights tab that surfaces two key
metrics — **profit per asset** (per-symbol realized P&L) and **average profit
per trade** — in a dedicated card at the **top of the Insights tab, above the
header card**. The data comes from the existing `TradeSummary` / `SymbolSummary`
models, so no new data layer is required.

## Behavioral Change

After this advance:
- The **Insights** tab shows a new `ProfitBreakdownView` card at the very top
  of the scroll view, before the "AI Insights" header card. It displays:
  - **Per-asset profit**: a compact list of the user's traded symbols, each with
    its realized P&L (green for profit, red for loss), sorted by P&L descending.
  - **Average profit per trade**: total realized P&L divided by sell count,
    displayed as a single metric at the bottom of the card.
- The card uses existing design-system components (`GlassCard`, `PnLLabel`)
  and reuses `TradeSummary` / `SymbolSummary` — no new models or services.
- The card refreshes **every time the user opens the Insights tab** via
  `.onAppear` → `processor.handle(.loadTradeSummary)`, which fetches trades
  from SwiftData and re-runs `TradePatternSummarizer.summarize`.
- The card also loads on initial `.task` alongside the existing `.load` intent.
- The card shows a "No trades yet" placeholder when there are no symbols.
- The card does **not** affect the Analyze flow, the chat flow, or any existing
  behavior — it is additive.

## Data Source

- `TradeSummary.totalRealizedPnL` and `TradeSummary.topSymbols` (each
  `SymbolSummary` carries `realizedPnL`) are computed by
  `TradePatternSummarizer` (ADV-AI-INSIGHTS-001). No new calculation needed.
- Average profit per trade = `totalRealizedPnL / sellCount` (guarded for zero
  division). This is a view-level derivation, not a stored field.
- The `loadTradeSummary` intent in `InsightsProcessor` fetches all `Trade`
  records from SwiftData and calls `summarizer.summarize(trades, now:)` to
  produce a fresh `TradeSummary`.

## Component Impact

- **ai-insights** (`EasyCrypto/Features/Insights/**`):
  - New `ProfitBreakdownView` — stateless view that takes a `TradeSummary` and
    renders the per-asset list + average metric using design-system components.
  - `InsightsState` — added `tradeSummary: TradeSummary = .empty` field.
  - `InsightsIntent` — added `case loadTradeSummary`.
  - `InsightsProcessor` — added `handle(.loadTradeSummary)` and
    `loadTradeSummary()` which fetches trades and summarizes them.
  - `InsightsView` — `profitBreakdownCard` (a `ProfitBreakdownView`) is now
    the first child of the scroll view's `VStack`, above `headerCard`. The
    `.task` modifier loads both insights and trade summary on first appear;
    `.onAppear` refreshes the trade summary every time the tab is opened.

## Out of Scope

- Detailed per-trade breakdown or drill-down into individual trades.
- Charts or sparklines (future enhancement).
- Changing the `TradeSummary` model or `TradePatternSummarizer`.
- Caching the trade summary — it re-derives from SwiftData on every tab open
  (cheap: pure computation over already-persisted trades).

## Implementation Tasks

- [x] test (ai-insights): `ProfitBreakdownView` renders per-asset rows sorted by
      P&L descending with correct sign coloring
- [x] test (ai-insights): `ProfitBreakdownView` shows "No trades yet" when
      `topSymbols` is empty
- [x] test (ai-insights): average profit per trade is computed correctly
      (totalRealizedPnL / sellCount, zero-division guard)
- [x] feat (ai-insights): `ProfitBreakdownView` using existing design-system
      components
- [x] feat (ai-insights): `tradeSummary` field added to `InsightsState`
- [x] feat (ai-insights): `loadTradeSummary` intent + processor logic
- [x] feat (ai-insights): `ProfitBreakdownView` wired into `InsightsView` at
      the top of the tab, above the header card
- [x] feat (ai-insights): auto-refresh via `.onAppear` + `.task` on tab open

## Bug Fixes

- [x] fix (ai-insights): handle on-device model refusal ("The model refused to answer") by softening prompt language, allowing 0-insight batches, and surfacing a user-friendly error message

## Risk + Rollback

- Risk: none — additive UI change, no new data path, no behavior change to
  existing flows. `TradeSummary` is already bounded and deterministic.
- Rollback: revert the advance's commits. No migration or data change needed.

## Evidence

- [x] tdd:red-green
- [x] tests:unit — `ProfitBreakdownViewTests.swift` (6 tests: sorting, avg profit,
       empty state)
- [x] bugfix: model refusal — `InsightEngineError.refused` + user-friendly error
       message, softened prompt to avoid financial-advice filter

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-AI-INSIGHTS-006 --status passed`

## Changes Made

### 2026-07-18 - feat(ai-insights): add profit breakdown screen with per-asset P&L and avg profit per trade
- `EasyCrypto/Features/Insights/ProfitBreakdownView.swift`: new stateless SwiftUI view
- `EasyCryptoTests/Features/Insights/ProfitBreakdownViewTests.swift`: 6 unit tests
- `EasyCrypto/Features/Insights/InsightsState.swift`: added `tradeSummary` field
- `EasyCrypto/Features/Insights/InsightsIntent.swift`: added `.loadTradeSummary`
- `EasyCrypto/Features/Insights/InsightsProcessor.swift`: added `loadTradeSummary()` handler
- `EasyCrypto/Features/Insights/InsightsView.swift`: wired `ProfitBreakdownView` at top of tab, auto-refresh on `.onAppear`

### 2026-07-18 - fix(ai-insights): handle model refusal error during insight generation
- `EasyCrypto/Core/AI/FoundationModelInsightEngine.swift`: added `InsightEngineError.refused` case; `LanguageModelInsightSession` catches refusal errors and maps to typed error
- `EasyCrypto/Core/AI/InsightGeneration.swift`: softened prompt to avoid financial-advice filter (removed "explain what they imply", "concise and actionable"); added informational-use disclaimer; changed schema to allow 0–5 insights (was 1–5)
- `EasyCrypto/Features/Insights/InsightsProcessor.swift`: surface user-friendly message on refusal instead of raw error string

## Check for Understanding

1. Where does the profit-per-asset data come from, and why doesn't this advance
   need a new model or service?
2. How is average profit per trade computed, and what guards prevent a
   divide-by-zero when there are no sells?
3. How does the trade summary refresh when the user opens the Insights tab,
   and why does it re-derive from SwiftData instead of caching?
4. What caused the on-device model to refuse insight generation, and how does
   the fix handle that error gracefully?
