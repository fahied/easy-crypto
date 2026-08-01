---
advance:
  id: "ADV-AI-INSIGHTS-007"
  title: "Fix profit breakdown to include all profitable symbols"
  system: "easycrypto-core"
  primary_component: "ai-insights"
  components: ["ai-insights", "core-models"]
  started_at: "2026-08-01T00:00:00Z"
  implementation_completed_at: "2026-08-01T00:00:00Z"
  review_time_estimate_minutes: 15
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  model_usage: []
  status: complete
---

## Objective

`ProfitBreakdownView` currently only displays the symbols that appear in `TradeSummary.topSymbols`, which is capped at 10 and ranked by trade count. Users with more than 10 traded symbols — or whose profitable symbols happen to have fewer trades than the cutoff — see an incomplete profit breakdown.

Re-rank `topSymbols` by realized P&L (descending) instead of trade count, so the breakdown reflects actual profit contribution rather than trading frequency. All entries within the cap are displayed by the view; no view-side change is needed.

## Behavioral Change

- Before: a user who profited from 8 symbols but traded 12 symbols total sees at most 8 (and possibly fewer if profitable symbols are not among the 10 most-traded).
- After: `topSymbols` is sorted by realized PnL descending, capped at 10. The same cap still applies but it now preserves the financially most-relevant symbols. Users with ≤10 symbols see all of them regardless of trade count.

## Risk + Rollback

- Risk: changing the sort key for `topSymbols` also affects `InsightGeneration` and `InsightChat`, which currently iterate `topSymbols` assuming trade-count order.
- Rollback: revert the sort comparator in `TradePatternSummarizer` back to trade count; no other files need changing.

## Changes Made

### 2026-08-01 - test: Add test asserting PnL ranking in topSymbols
- EasyCryptoTests/Core/AI/TradePatternSummarizerTests.swift: Added `topSymbolsRankedByPnL()` test that creates 11 symbols where SYM1 has highest PnL (+500) but fewest trades (2), verifying it appears first in `topSymbols` despite being outranked by trade count under the old logic

### 2026-08-01 - fix: Re-rank topSymbols by realized PnL descending
- EasyCrypto/Core/AI/TradePatternSummarizer.swift: Changed sort comparator in `summarize()` (line 82–86) from trade-count descending to realized PnL descending, with trade count as tiebreaker. Previously ranked symbols by `tradeCount` (desc) then `symbol` (asc); now ranks by `realizedPnL` (desc) then `tradeCount` (desc).

## Check for Understanding

1. In `TradePatternSummarizer.summarize()`, what changed in the sort comparator and why?
2. What is the tiebreaker when two symbols have identical realized PnL?
3. Which view was affected by this bug, and why does it need no code change?
4. Name one consumer of `topSymbols` other than `ProfitBreakdownView` and explain how it benefits from PnL ordering.
