# FIFO Cost Basis & Average Price Calculations

> **Authoritative implementation**: `EasyCrypto/Core/Services/FIFOCalculator.swift`
> — `fifoCompute()` (lines 80-148) and `fifoComputeBreakdowns()` (lines 150-229).
>
> **Mirror implementation**: `scripts/validate_daily_profit.py` — `fifo_compute_breakdowns()`.

---

## 1. Binance Trade Data (from `/api/v3/myTrades`)

Each trade record from the Binance Spot API contains:

| Field | Meaning |
|-------|---------|
| `price` | Per-unit price in quote asset (e.g., 50,000 USDT per BTC) |
| `qty` | Quantity in base asset (e.g., 0.5 BTC) |
| `quoteQty` | `price × qty` — USDT value of the trade |
| `commission` | Fee amount paid |
| `commissionAsset` | Asset the fee was paid in (base asset, quote asset, or BNB) |
| `isBuyer` | `true` = buy, `false` = sell |

The app maps these to `FIFOTrade` in `TradeImportService` and `Trade` (SwiftData).

---

## 2. Weighted Average Buy Price (Remaining Lots)

The **weighted average buy price** is the per-unit cost basis of all lots still held after
FIFO sells consume the earliest lots first.

### Formula

```
totalRemainingQty = Σ(lot.remainingQuantity)           # sum of all remaining lot sizes
totalInvested     = Σ(lot.price × lot.remainingQuantity)  # total USD still invested
weightedAvg       = totalInvested / totalRemainingQty
```

### How It Evolves

- Each **buy** adds a new lot → both numerator and denominator grow.
- Each **sell** consumes from the earliest lot(s) → both shrink proportionally.
- The average **recalculates** after every sell based on remaining lots only.

This is the correct cost basis for computing unrealized P&L on current holdings.

---

## 3. The Base-Asset Commission Bug and Its Fix

### The Original Problem

When Binance charges commission in the **base asset** (e.g., BTC fee on a BTC/USDT buy), two
things happen simultaneously:

1. **Quantity received** = `qty − commission` (you get less BTC than you paid for)
2. **USD spent** = `price × qty` (you paid for the full `qty` at `price`)

**The bug** (present in the initial FIFO implementation): the engine correctly reduced the
lot quantity by the commission but left the lot price at `trade.price`. This made the lot's
cost contribution wrong:

```
# BUGGY — before commit 3803085:
lot.price = trade.price              # 50,000 USDT/BTC (full trade price)
lot.remainingQuantity = qty - fee    # 0.999 BTC (after 0.001 BTC commission)
lot cost = 50,000 × 0.999 = 49,950 USDT   ← undercounted by 50 USDT
```

The 50 USDT commission cost was silently dropped from cost basis. Over many buys, this
compounded into a significant understatement of the average buy price.

### The Fix (commit 3803085 — ADV-CORE-SERVICES-010)

Inflate the lot price so that `lot.price × lot.remainingQuantity` equals the **total USD
actually spent** on the buy:

```swift
let netQty = trade.quantity - trade.commission   // what you actually received
let effectivePrice = trade.price * trade.quantity / netQty
lots.append(BuyLot(price: effectivePrice, remainingQuantity: netQty))
```

```
# FIXED:
lot.price = 50,000 × 1.0 / 0.999 ≈ 50,050.05
lot.remainingQuantity = 0.999
lot cost = 50,050.05 × 0.999 = 50,000 USDT   ✓ matches total USD spent
```

### Core Invariant

For every buy lot, after the fix:

```
lot.price × lot.remainingQuantity = trade.price × trade.quantity  (= total USD spent)
```

This invariant holds regardless of commission asset type:
- **Base asset commission**: price is inflated, quantity is reduced.
- **Quote asset commission (e.g., USDT fee)**: price stays at `trade.price`, quantity is
  unchanged — the invariant holds trivially (`price × qty = price × qty`).
- **BNB commission (neither base nor quote)**: same as quote asset — no impact on the lot.

---

## 4. FIFO Lot Consumption on Sells

When a sell occurs, quantity is consumed from the earliest (oldest) lots first.

### Sell-Side Commission: Three Cases

#### Case A: Commission in Base Asset

The commission is an **additional quantity drain** from the lot, separate from the sold
quantity that the counterparty receives.

```
sellQty           = trade.quantity + commission   # total to consume from lots
soldPortion       = trade.quantity                 # what the buyer receives
feePortion        = commission                     # paid as fee, not sold
```

P&L impact:

```
realizedPnL += soldPortion × (sellPrice - lot.price)    # gain on sold portion
realizedPnL -= feePortion × lot.price                    # cost basis of fee portion
```

The fee portion reduces `realizedPnL` by `feePortion × lot.price` because `lot.price` is
the inflated cost basis — this correctly accounts for the USD value of the base-asset
commission.

#### Case B: Commission in Quote Asset (e.g., USDT)

The commission is a **flat USDT deduction** from realized P&L:

```
realizedPnL -= trade.commission
```

No impact on lot consumption — the fee is paid in USDT, not in the base asset.

#### Case C: Commission in BNB (neither base nor quote)

No impact on P&L at all — the fee is paid in a third asset. The lot is consumed only by the
sold quantity.

### Partial Lot Consumption

When a sell does not fully consume a lot:

```
consumed     = min(lot.remainingQuantity, sellQty)
soldPortion  = min(consumed, trade.quantity)
feePortion   = consumed - soldPortion

lot.remainingQuantity -= consumed
```

The lot retains its original `lot.price` for the remaining quantity. The weighted average
price of the lot does not change.

### Sell with No Remaining Lots

If there are no lots to consume (e.g., sell before any buy, or all lots exhausted), the
sell is silently ignored. `realizedPnL` is unchanged and no `SaleBreakdown` is produced.

---

## 5. Per-Sell Cost Basis Breakdown

Each sell produces a `SaleBreakdown`:

| Field | Formula |
|-------|---------|
| `costBasisAmount` | Σ(soldPortion × lot.price) across all consumed lots |
| `costBasisPrice` | costBasisAmount / soldQuantity (weighted avg of consumed lots) |
| `realizedPnL` | Σ(soldPortion × (sellPrice − lot.price)) − fee costs − USDT commission |
| `borrowingFee` | soldQuantity × feePerUnit (margin trades only) |

### Worked Example

```
Buy:  1.0 BTC @ 50,000 USDT, commission 0.001 BTC (base asset)
  netQty  = 1.0 − 0.001 = 0.999
  lotPrice = 50,000 × 1.0 / 0.999 = 50,050.05
  lot = {price: 50,050.05, remaining: 0.999}

Sell: 0.999 BTC @ 55,000, commission 0.0005 BTC (base asset)
  sellQty          = 0.999 + 0.0005 = 0.9995
  consumed         = min(0.999, 0.9995) = 0.999
  soldPortion      = min(0.999, 0.999) = 0.999
  feePortion       = 0.999 − 0.999 = 0

  PnL from sale: 0.999 × (55,000 − 50,050.05) = 4,944.95
  PnL from fee:  0 × 50,050.05 = 0
  realizedPnL = 4,944.95

  costBasisPrice   = 50,050.05
  costBasisAmount  = 0.999 × 50,050.05 = 49,999.95
  remaining lots   = [] (all consumed)
```

---

## 6. Borrowing Fees (Margin)

Borrowing fees are provided as a per-unit cost (USDT per unit sold). They are deducted from
`realizedPnL` proportional to the quantity sold:

```
borrowingFee = soldQuantity × borrowingFeePerUnit
realizedPnL -= borrowingFee
```

Applied in:
- `fifoComputeBreakdowns()` — per-sell `SaleBreakdown` (line 210-215)
- `calculateMargin()` — aggregate margin-adjusted P&L (line 284-290)

---

## 7. Unrealized P&L

Computed in `HoldingFactory.make()` and `CoinDetailProcessor.loadDetail()`:

```
currentValue       = totalRemainingQuantity × currentPrice
totalInvested      = Σ(lot.price × lot.remainingQuantity)   # from FIFO result
unrealizedPnL      = currentValue − totalInvested
unrealizedPnL%     = unrealizedPnL / totalInvested × 100
```

Key point: `totalInvestedUSDT` comes from the FIFO result (sum of `lot.price × remaining`),
not from `weightedAvgBuyPrice × walletQuantity`. The wallet quantity from the balance API
may differ from the FIFO remaining quantity (e.g., due to dust, unreported trades, or pending
deposits), so the FIFO-derived invested amount is used for P&L accuracy.

---

## 8. Dust Filter (epsilon)

Trades with net quantity below `epsilon = 1.0` (after commission deduction) are excluded
from the FIFO lot queue. This matches Binance's behavior of filtering tiny trades from
average price calculations.

```swift
let epsilon = 1.0
// ...
if qty > epsilon {
    lots.append(...)
}
```

The dust filter prevents micro-trades from distorting the weighted average for assets with
prices in the thousands of USDT range.

---

## 9. Complete Numeric Walkthrough

### Scenario

```
Buy 1:  2.0 BTC @ 50,000 USDT, commission 0.001 BTC
Buy 2:  1.0 BTC @ 60,000 USDT, commission 0.001 BTC
Sell 1: 1.0 BTC @ 55,000, commission 0.001 USDT
```

### Step-by-step

**Buy 1** (2.0 BTC @ 50,000, commission 0.001 BTC):
```
netQty   = 2.0 − 0.001 = 1.999
lotPrice = 50,000 × 2.0 / 1.999 = 50,025.0125
lot 1 = {price: 50,025.0125, remaining: 1.999}
totalInvested = 50,025.0125 × 1.999 = 100,000  ✓
```

**Buy 2** (1.0 BTC @ 60,000, commission 0.001 BTC):
```
netQty   = 1.0 − 0.001 = 0.999
lotPrice = 60,000 × 1.0 / 0.999 = 60,060.060
lot 2 = {price: 60,060.060, remaining: 0.999}
totalInvested = 50,025.0125×1.999 + 60,060.060×0.999 = 159,975.01 + 60,000 = 219,975.01
totalRemainingQty = 1.999 + 0.999 = 2.998
weightedAvg = 219,975.01 / 2.998 ≈ 73,365.24
```

**Sell 1** (1.0 BTC @ 55,000, commission 0.001 USDT):
```
sellQty           = 1.0  (no base-asset fee)
consumed          = min(1.999, 1.0) = 1.0   (from lot 1)
soldPortion       = 1.0
feePortion        = 0

PnL: 1.0 × (55,000 − 50,025.0125) = 4,974.99
PnL: − 0.001 (USDT commission)
realizedPnL = 4,974.99

After sell:
lot 1 remaining = 1.999 − 1.0 = 0.999
lot 2 unchanged  = {price: 60,060.060, remaining: 0.999}

totalInvested = 50,025.0125×0.999 + 60,060.060×0.999 = 49,975.01 + 60,000 = 109,975.01
totalRemainingQty = 0.999 + 0.999 = 1.998
weightedAvg = 109,975.01 / 1.998 ≈ 55,030.28
```

### Verification

```
Total USD spent on buys: 50,000×2.0 + 60,000×1.0 = 160,000
Total BTC received:      (2.0−0.001) + (1.0−0.001) = 2.998
Simple avg across all:   160,000 / 2.998 ≈ 53,369.58  (Binance "Avg Buy" display)

FIFO weighted avg of remaining lots: ≈ 55,030.28  (cost basis for unrealized P&L)
```

The two averages differ because the FIFO average only considers remaining holdings (after
consuming the cheapest lot first), while Binance's "Avg Buy" is a simple average across all
buys regardless of sells.

---

## 10. Summary of All Calculation Paths

| Calculation | Used In | Formula |
|-------------|---------|---------|
| `weightedAvgBuyPrice` | Holdings display, unrealized P&L | Σ(price×qty) / Σ(qty) over remaining FIFO lots |
| `totalInvestedUSDT` | Holdings "Invested" value | Σ(price×qty) over remaining lots |
| `realizedPnL` | Trade History, Portfolio | Σ(soldPortion×(sellPrice−lotPrice)) − fee costs − USDT commission |
| `costBasisPrice` | Trade History per-sell row | Σ(soldPortion×lotPrice) / soldQuantity |
| `costBasisAmount` | Trade History daily totals | Σ(soldPortion×lotPrice) |
| `marginAdjustedRealizedPnL` | Margin Trade History | realizedPnL − Σ(borrowingFees) |
| `unrealizedPnL` | Holdings, Coin Detail | currentValue − totalInvestedUSDT |
| `simpleAvgBuyPrice` | *(removed in 6d3bca1)* | totalSpent / totalReceived across all buys |

---

## 11. Failure History

| Commit | What Happened | Root Cause |
|--------|--------------|------------|
| `587961e` | FIFO calculator introduced | Buy lots used `trade.price` without inflating for base-asset commission |
| `3803085` | ADV-010 fix | Inflated lot prices: `lotPrice = trade.price × qty / netQty` |
| `383f486` | ADV-011 added `simpleAvgBuyPrice` | Attempted to match Binance display, but wrong metric for cost basis |
| `6d3bca1` | Reverted ADV-011 | `simpleAvgBuyPrice` removed; `epsilon = 1.0` dust filter added; `weightedAvgBuyPrice` restored as authoritative cost basis |
| `ad1792d` (current HEAD) | Clean state | Base-asset commission inflation + dust filter + weighted average; all 410 tests pass |

The current codebase has the correct implementation:
- Lot prices are inflated when commission is in the base asset.
- Dust trades (< 1.0 unit) are filtered via `epsilon = 1.0`.
- `weightedAvgBuyPrice` from remaining FIFO lots is the authoritative cost basis.
- Sell-side commission is handled correctly in all three cases (base asset, quote asset, BNB).
