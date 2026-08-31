---
advance:
  id: "ADV-CORE-SERVICES-011"
  title: "Revert to weightedAvgBuyPrice — simpleAvg was the wrong metric for display"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "features-holdings"]
  started_at: "2026-08-31T00:00:00Z"
  implementation_completed_at: "2026-08-31T00:00:00Z"
  review_time_estimate_minutes: 15
  review_time_actual_minutes:
  pr_links: []
  reviewability_score: 10
  risk_flags: []
  evidence: ["tdd:red-green", "tidy:preparatory", "tests:unit"]
  status: complete
  blocks: ["ADV-CORE-SERVICES-010"]
  supersedes: ["ADV-CORE-SERVICES-011-v1"]
---

## Objective

Revert the `simpleAvgBuyPrice` wiring introduced in ADV-011-v1. `simpleAvgBuyPrice`
divides lifetime USD spent across all buy trades by lifetime quantity received — old
fully-sold trades pull the average down. This is wrong for a portfolio tracker where
the user wants to know the cost basis of what they currently hold.

Use `weightedAvgBuyPrice` instead — it averages only the remaining FIFO lots, so it
correctly reflects what was actually paid for what is currently held.

## Root Cause

`simpleAvgBuyPrice` was introduced to mimic Binance's spot "Avg Buy" display. But that
metric conflates closed and open positions:

| Scenario | simpleAvgBuyPrice | weightedAvgBuyPrice |
|---|---|---|
| 1 buy, no sells | $78,084 | $78,084 |
| Buy @ $70k, Buy @ $78k, no sells | $74,042 | $74,042 |
| Buy @ $70k (sold), Buy @ $78k (held) | **$74,042** | **$78,084** ✓ |

In the third case, `simpleAvgBuyPrice` includes the sold $70k lot — dragging the
average down and overstating the cost basis of the current position.

## Fix

### 1. HoldingFactory.make() — use weightedAvgBuyPrice

```swift
let avgBuyPrice = fifo.weightedAvgBuyPrice  // was fifo.simpleAvgBuyPrice
```

### 2. CoinDetailProcessor.loadDetail() — use weightedAvgBuyPrice

```swift
let avgBuyPrice = result.weightedAvgBuyPrice  // was result.simpleAvgBuyPrice
```

Also passes `tradingMode` through the intent so the detail view filters trades by mode,
matching the Holdings tab. The Holding is now constructed with `tradingMode`.

### 3. UnrealizedProfit.compute() — use weightedAvgBuyPrice

```swift
let invested = result.weightedAvgBuyPrice * result.totalRemainingQuantity
// was result.simpleAvgBuyPrice * result.totalRemainingQuantity
```

## Files Changed

| File | Change |
|---|---|
| `EasyCrypto/Core/Services/HoldingFactory.swift` | `fifo.weightedAvgBuyPrice` instead of `fifo.simpleAvgBuyPrice` |
| `EasyCrypto/Features/Holdings/CoinDetailProcessor.swift` | `result.weightedAvgBuyPrice`; pass `tradingMode` through intent and predicate |
| `EasyCrypto/Core/Services/UnrealizedProfit.swift` | `result.weightedAvgBuyPrice * result.totalRemainingQuantity` |
| `EasyCrypto/Features/Holdings/CoinDetailIntent.swift` | Added `tradingMode` parameter to `loadDetail(asset:tradingMode:)` with default `.spot` |

## Behavioral Change

- **Holdings tab "Avg Buy"**: now reflects the cost basis of remaining lots only.
  Changes after sells — correctly.
- **Coin detail "Avg Cost"**: same value as Holdings tab for consistency.
- **Invested**: `weightedAvgBuyPrice × walletQuantity` — actual cost of what's held.
- **Price alert unrealized P&L**: computed from weighted average, consistent with holdings.

## Risk

- Low: `weightedAvgBuyPrice` was the original correct metric. `simpleAvgBuyPrice` is
  retained as a computed property on `FIFOResult` for any future use.
- No schema changes; no API changes.

## Check for Understanding

1. Why is `simpleAvgBuyPrice` misleading for a portfolio tracker after sells?
2. Why does `weightedAvgBuyPrice` change after a sell, and is that the correct behavior?
3. Why must the CoinDetailProcessor filter trades by `tradingMode` to match the Holdings tab?
