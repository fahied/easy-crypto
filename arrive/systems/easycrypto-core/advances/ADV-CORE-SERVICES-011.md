---
advance:
  id: "ADV-CORE-SERVICES-011"
  title: "Wire simpleAvgBuyPrice (Binance-style) as the display avg for Holdings"
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
---

## Objective

Wire up the `simpleAvgBuyPrice` (Binance-style) that was added in ADV-010 into the
HoldingFactory and CoinDetailProcessor so that both the Holdings tab and the per-coin
detail screen display the same avg buy price Binance shows. Also update UnrealizedProfit
to match.

## Context — What ADV-010 Fixed vs What It Didn't

ADV-010 fixed **lot price inflation** for base-asset commission buys (the FIFO engine's
cost basis was wrong). It also added `totalBoughtUSDT`, `totalBoughtQuantity`, and
`simpleAvgBuyPrice` to `FIFOResult` — a Binance-style average that divides total USD
spent across all buys by total net quantity received, never changing after sells.

However, ADV-010 did **not** update the consumers of `FIFOResult` to use the new
`simpleAvgBuyPrice`. Both `HoldingFactory.make()` and `CoinDetailProcessor.loadDetail()`
continued to use `weightedAvgBuyPrice` (FIFO-weighted over remaining lots), which is
correct for tax cost basis but wrong for Binance display parity.

## Root Cause (Display Layer)

| Consumer | Field Used | Result |
|---|---|---|
| `HoldingFactory.make()` | `fifo.weightedAvgBuyPrice` | FIFO-weighted over remaining lots |
| `CoinDetailProcessor.loadDetail()` | `result.weightedAvgBuyPrice` + `result.totalInvestedUSDT` | FIFO-weighted |
| `UnrealizedProfit.compute()` | `result.totalInvestedUSDT` | FIFO-weighted remaining |

After any sell, `weightedAvgBuyPrice` shifts because only unsold lots contribute.
Binance's "Avg Buy" never shifts.

### Concrete Example

Two buys, one partial sell:

| Trade | Type | Price | Qty | Commission | USD Spent | Net Qty |
|---|---|---|---|---|---|---|
| Buy 1 | buy | $60,000 | 0.01 | 0.00001 BTC | $600.00 | 0.00999 |
| Buy 2 | buy | $65,000 | 0.01 | 0.00001 BTC | $650.00 | 0.00999 |
| Sell | sell | $70,000 | 0.005 | 0.00001 BTC | — | — |

After sell, 0.00498 BTC remains (all from Buy 2):

```
Binance simpleAvg: (600 + 650) / (0.00999 + 0.00999) = 62,562.56
FIFO weightedAvg: 65,000 (only Buy 2 lot remains)
```

The Holdings tab was showing $65,000, Binance shows $62,562.56.

## Fix

### 1. HoldingFactory.make() — use simpleAvgBuyPrice

```swift
let avgBuyPrice = fifo.simpleAvgBuyPrice  // was fifo.weightedAvgBuyPrice
```

All downstream derived fields (`invested`, `unrealizedPnL`, `unrealizedPnLPercent`)
automatically follow because they depend on `avgBuyPrice`.

### 2. CoinDetailProcessor.loadDetail() — use simpleAvgBuyPrice

Same change. Also rebuilt `invested` from `avgBuyPrice × remainingQuantity` instead
of using `result.totalInvestedUSDT` (which is FIFO-weighted).

### 3. UnrealizedProfit.compute() — use simpleAvgBuyPrice

Rebuilt `invested = simpleAvgBuyPrice × totalRemainingQuantity` to match display.

## Files Changed

| File | Change |
|---|---|
| `EasyCrypto/Core/Services/HoldingFactory.swift` | `fifo.simpleAvgBuyPrice` instead of `fifo.weightedAvgBuyPrice` |
| `EasyCrypto/Features/Holdings/CoinDetailProcessor.swift` | `result.simpleAvgBuyPrice`; rebuild invested from avg price × quantity |
| `EasyCrypto/Core/Services/UnrealizedProfit.swift` | `result.simpleAvgBuyPrice * result.totalRemainingQuantity` |

## Behavioral Change

- **Holdings tab "Avg Buy"**: now matches Binance's "Avg Buy" exactly — total USD spent
  on all buys / total net quantity received. Does not change after sells.
- **Coin detail "Avg Cost"**: same value as Holdings tab for consistency.
- **Portfolio "Invested"**: now uses `avgBuyPrice × walletQuantity` instead of FIFO
  weighted sum of remaining lots. More accurate representation of user's total spend.
- **Price alert unrealized P&L**: computed from same display avg, consistent with app.

## Verification

- FIFO calculator tests pass (inflation, breakdowns, margin).
- HoldingsFactory and CoinDetailProcessor don't have standalone unit tests but
  build cleanly and flow correctly through the full app.

## Risk

- Low: `FIFOResult.simpleAvgBuyPrice` is a computed property that gracefully falls
  back to `weightedAvgBuyPrice` when no buys exist (both are 0).
- No schema changes; no API changes.
- Only affects display values — FIFO tax calculations are unchanged.

## Rollback

Revert the three consumer files to use `weightedAvgBuyPrice` / `totalInvestedUSDT` again.

## Check for Understanding

1. Why does `weightedAvgBuyPrice` shift after a sell while `simpleAvgBuyPrice` doesn't?
2. Why must `HoldingFactory` use the wallet's authoritative quantity (`quantity` param)
   rather than `result.totalRemainingQuantity` when computing invested?
3. Why does `UnrealizedProfit.compute()` need the same simpleAvg treatment as the UI?
