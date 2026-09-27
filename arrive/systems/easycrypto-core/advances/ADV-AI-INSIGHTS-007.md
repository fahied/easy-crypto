---
advance:
  id: "ADV-AI-INSIGHTS-007"
  title: "Fix profit breakdown P&L ranking and average holding period"
  system: "easycrypto-core"
  primary_component: "ai-insights"
  components: ["ai-insights", "core-models"]
  started_at: "2026-08-01T00:00:00Z"
  implementation_completed_at: "2026-08-01T00:00:00Z"
  review_time_estimate_minutes: 20
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  model_usage: []
  status: complete
---

## Objective

Two bugs in `TradePatternSummarizer` produce misleading Insight tab metrics:

1. **Profit breakdown exclusion**: `topSymbols` is capped at 10 and ranked by trade count, so profitable symbols with fewer trades are silently dropped from `ProfitBreakdownView`.
2. **Inflated average holding period**: the old code measured span from the *first buy ever* to the *last sell ever* per symbol, producing multi-month averages for users who round-trip frequently.

Both bugs are fixed in `TradePatternSummarizer.summarize()`.

## Behavioral Change

- Before: profit breakdown shows at most 10 symbols ranked by trade frequency; holding period measures the full symbol span (first buy → last sell).
- After: `topSymbols` is ranked by realized PnL descending (trade count as tiebreaker). Holding period averages the span of each individual round-trip (FIFO buy-lot to the sell that consumed it), giving a true per-trade exposure duration.

## Risk + Rollback

- Risk: changing the sort key for `topSymbols` also affects `InsightGeneration` and `InsightChat`, which currently iterate `topSymbols` assuming trade-count order.
- Rollback: revert both the sort comparator and the holding-span loop in `TradePatternSummarizer` to their original forms; no other files need changing.

## Changes Made

### 2026-08-01 - test: Add tests for PnL ranking and per-round-trip holding period
- EasyCryptoTests/Core/AI/TradePatternSummarizerTests.swift: Added `topSymbolsRankedByPnL()` — 11 symbols where SYM1 has highest PnL (+500) but only 2 trades (others have 12 each), asserting SYM1 appears first in `topSymbols`. Added `averageHoldingPeriodPerRoundTrip()` — two round-trips within one week, asserting average is 1 day not 8.

### 2026-08-01 - fix: Rank topSymbols by realized PnL and compute per-round-trip holding periods
- EasyCrypto/Core/AI/TradePatternSummarizer.swift: Changed sort comparator (line 116–120) from trade-count descending to realized PnL descending, trade count as tiebreaker. Replaced the first-buy/last-sell holding span with a FIFO lot-queue walk that pairs each sell with the specific buy lots it consumed, computing a weighted-average buy timestamp per round-trip. Each individual round-trip span is then averaged across all sells across all symbols.

## Check for Understanding

1. What was wrong with the old holding-period calculation, and why did it produce 34+ days for short-term traders?
2. How does the new lot-queue walk compute the buy timestamp for each round-trip?
3. Why is realized PnL a better sort key than trade count for `topSymbols` in the context of `ProfitBreakdownView`?
4. If two symbols have the same realized PnL, how does the tiebreaker decide which one appears first in `topSymbols`?
