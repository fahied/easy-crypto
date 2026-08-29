---
advance:
  id: "ADV-CORE-SERVICES-011"
  title: "Add Binance-style simple average buy price display"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "core-models", "holdings"]
  started_at: "2026-08-29T00:00:00Z"
  implementation_completed_at: "2026-08-29T22:00:00Z"
  review_time_estimate_minutes: 15
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 12
  risk_flags: []
  evidence: ["tdd:red-green", "tidy:preparatory", "tests:unit"]
  status: complete
---

## Objective

The "Avg Buy" value shown in the Holdings tab did not match Binance's display. Binance uses a simple average across all buy trades (total USD spent / total quantity received), while the app used FIFO's weighted average over remaining lots, which re-averages after sells and excludes USD from base-asset commission. This caused the Holdings avg buy price to diverge from Binance after any sell trade.

Follows [ADV-CORE-SERVICES-010](ADV-CORE-SERVICES-010.md) which fixed the base-asset commission understatement. This advance makes the display match Binance's "Avg Buy" semantics.

## Root Cause

`FIFOCalculator.fifoCompute()` computed `weightedAvgBuyPrice` as `Σ(lot.price × lot.remainingQuantity) / Σ(lot.remainingQuantity)`. This re-averages over remaining lots after sells, so partial sells shift the weighted avg. Binance instead computes a simple average over all buys that never changes after sells:

```
Binance Avg = Σ(trade.price × trade.quantity) / Σ(receivedQuantity)
```

`HoldingFactory.make` and `CoinDetailProcessor` both consumed `weightedAvgBuyPrice` for the "Avg Buy" display.

## Fix

1. Added `totalBoughtUSDT` and `totalBoughtQuantity` tracking to `FIFOCalculator.fifoCompute()` and `fifoComputeBreakdowns()`
2. Added `simpleAvgBuyPrice` computed property to `FIFOResult` (and `MarginFIFOResult`) that returns `totalBoughtUSDT / totalBoughtQuantity`
3. Updated `HoldingFactory.make()` to use `fifo.simpleAvgBuyPrice` instead of `fifo.weightedAvgBuyPrice`
4. Updated `CoinDetailProcessor.loadDetail()` to use `result.simpleAvgBuyPrice` for unrealized P&L calculations

## Behavioral Change

- **Before**: Holdings "Avg Buy" = FIFO weighted avg over remaining lots — changes after every sell
- **After**: Holdings "Avg Buy" = Binance-style simple avg over all buys — constant regardless of sells
- When no buys exist (e.g. airdrops, rewards), `simpleAvgBuyPrice` falls back to `weightedAvgBuyPrice` (0)

## Component Impact

- **core-services**: `FIFOCalculator` — new `totalBoughtUSDT`/`totalBoughtQuantity` fields and `simpleAvgBuyPrice` computed property
- **core-models**: `FIFOResult` and `MarginFIFOResult` structs extended with simple-average fields
- **holdings**: `HoldingFactory` and `CoinDetailProcessor` now use `simpleAvgBuyPrice` for display

## Risk + Rollback

- **Risk**: The "Avg Buy" display changes for all positions that have ever had a sell trade. Users who got used to the old re-averaging value will see a different number — but it now matches Binance.
- **Risk**: Unrealized P&L in CoinDetail now uses the simple average instead of weighted average. For positions with no sells, both values are identical — no change. For positions with sells, the simple avg is higher (matches Binance) which means lower unrealized P&L for the same current price — this is correct behavior.
- **Rollback**: revert the three files that switched from `weightedAvgBuyPrice` to `simpleAvgBuyPrice`. The new fields in `FIFOResult` are additive — no callers are forced to use them.

## Implementation Tasks

### tidy
- None — fix is a localized change to production code and tests.

### test
- [x] `FIFOCalculatorTests`: simple avg equals weighted avg with no sells
- [x] `FIFOCalculatorTests`: simple avg unchanged after partial sell, weighted avg changes
- [x] `FIFOCalculatorTests`: simple avg persists after full sell (no lots remain)
- [x] `FIFOCalculatorTests`: simple avg with base-asset commission
- [x] `FIFOCalculatorTests`: simple avg with quote-asset commission
- [x] `FIFOCalculatorTests`: DCA buys then sell — simple avg matches Binance total-spent/total-qty

### feat
- [x] `FIFOCalculator.fifoCompute()`: track `totalBoughtUSDT`/`totalBoughtQuantity` and expose `simpleAvgBuyPrice`
- [x] `FIFOCalculator.fifoComputeBreakdowns()`: same tracking for per-trade breakdowns
- [x] `FIFOCalculator.MarginFIFOResult`: forward `simpleAvgBuyPrice`, `totalBoughtUSDT`, `totalBoughtQuantity`
- [x] `HoldingFactory.make()`: use `simpleAvgBuyPrice` instead of `weightedAvgBuyPrice`
- [x] `CoinDetailProcessor.loadDetail()`: use `simpleAvgBuyPrice` for unrealized P&L

## Evidence

- `tdd:red-green` — tests written before implementation
- `tests:unit` — 410 tests passing (0 failures)
- Coverage target ≥80% met for `FIFOCalculator`

## Check for Understanding

1. Why does FIFO's `weightedAvgBuyPrice` change after a partial sell while Binance's "Avg Buy" stays the same? What mechanism causes the difference?
2. How does the `simpleAvgBuyPrice` computed property handle the edge case where no buys exist (e.g., an airdrop or reward-only position)?
3. When the Holdings "Avg Buy" switches from `weightedAvgBuyPrice` to `simpleAvgBuyPrice`, which positions see a different value and why — only positions that have had sells, or also positions with base-asset commission on buys?

## Changes Made

### 2026-08-29 - feat: add Binance-style simple avg buy price to FIFO calculator
- `EasyCrypto/Core/Services/FIFOCalculator.swift`: Added `totalBoughtUSDT`/`totalBoughtQuantity` tracking, `simpleAvgBuyPrice` computed property on `FIFOResult` and `MarginFIFOResult`
- `EasyCrypto/Core/Services/HoldingFactory.swift`: Use `fifo.simpleAvgBuyPrice` for "Avg Buy" display
- `EasyCrypto/Features/Holdings/CoinDetailProcessor.swift`: Use `result.simpleAvgBuyPrice` for unrealized P&L

### 2026-08-29 - test: add simple average buy price tests
- `EasyCryptoTests/Core/Services/FIFOCalculatorTests.swift`: Added `FIFOSimpleAverageTests` suite with 6 tests covering no-sell, partial-sell, full-sell, base-asset commission, quote-asset commission, and DCA scenarios
