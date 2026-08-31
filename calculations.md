# Calculations.md — Average Buy Price Methodology

## Overview

The app needs to match Binance's "Avg Buy" display for each asset. This document
explains exactly how Binance computes that value, how the codebase computes it,
and why each step is necessary.

---

## Binance API Trade Structure

A single trade returned by `/api/v3/myTrades` (spot) or
`/sapi/v1/margin/myTrade` (margin) looks like:

```json
{
  "price": "60000.00",
  "quantity": "0.001",
  "quoteQty": "60.00",
  "commission": "0.000001",
  "commissionAsset": "BTC",
  "isBuyer": true
}
```

| Field | Meaning |
|---|---|
| `price` | Per-unit price in quote asset (USDT for BTC/USDT) |
| `quantity` | Base-asset quantity **before** commission |
| `quoteQty` | Total USDT spent: `price × quantity` |
| `commission` | Fee paid, denominated in `commissionAsset` |
| `commissionAsset` | Which currency the fee was paid in |
| `isBuyer` | `true` = buy, `false` = sell |

Binance returns **10,000 trades per call** with `limit=1000` per request.

---

## Commission Types

### Base-asset commission (`commissionAsset == asset`)

```
Buy:  price=60,000, quantity=0.001, commission=0.000001 BTC
You receive: 0.001 − 0.000001 = 0.000999 BTC
You spend:   60,000 × 0.001 = 60.00 USDT
```

### Quote-asset commission (`commissionAsset == "USDT"`)

```
Buy:  price=60,000, quantity=0.001, commission=0.01 USDT
You receive: 0.001 BTC (full quantity)
You spend:   60,000 × 0.001 + 0.01 = 60.01 USDT
```

### No commission

```
Buy:  price=60,000, quantity=0.001, commission=0, commissionAsset=""
You receive: 0.001 BTC
You spend:   60,000 × 0.001 = 60.00 USDT
```

---

## Binance "Avg Buy" Formula

On the Binance trade history page, the "Avg Buy" column shows:

```
Avg Buy = Σ(USD spent on all buys) / Σ(net quantity received on all buys)
```

**Key**: this value never changes after you sell. It is a running average across
**all buy trades only**, regardless of how much you have sold.

### Example: Two buys, one sell

| Trade | Type | Price | Qty | Commission | Net Qty | USD Spent |
|---|---|---|---|---|---|---|
| Buy #1 | buy | 60,000 | 0.01 | 0.00001 BTC | 0.00999 | 600.00 |
| Buy #2 | buy | 65,000 | 0.01 | 0.00001 BTC | 0.00999 | 650.00 |
| Sell | sell | 70,000 | 0.01 | 0.00001 BTC | — | 700.00 |

```
Total USD spent: 600 + 650 = 1,250
Total net qty:   0.00999 + 0.00999 = 0.01998
Binance Avg Buy: 1,250 / 0.01998 = 62,562.56
```

After the sell, you still have 0.00999 BTC and the "Avg Buy" stays at 62,562.56.

---

## FIFO Weighted Avg (Different Calculation)

FIFO weighted avg computes over **remaining lots only** (lots not yet sold):

```
weightedAvg = Σ(lot.price × lot.remainingQuantity) / Σ(lot.remainingQuantity)
```

After the sell above:

```
Remaining: 0.00999 BTC (Buy #2)
weightedAvg: 65,000 × 0.00999 / 0.00999 = 65,000
```

This differs from Binance's 62,562.56. This is expected and correct for
tax-reporting purposes, but it does **not** match the Binance display.

**The app now uses `simpleAvgBuyPrice` (Binance-style) for display** to match
what users see on Binance.

---

## App Calculations

### 1. Lot Price Inflation (Base-asset Commission)

When commission is paid in the base asset, the lot price must be inflated:

```swift
let netQty = trade.quantity − trade.commission
let lotPrice = trade.price × trade.quantity / netQty
```

Without inflation: `lot.price × lot.remainingQuantity = price × (quantity − commission)`
→ excludes the USD value of the commission.

With inflation: `lot.price × lot.remainingQuantity = price × quantity`
→ correctly includes the full USD spend.

**Example**: Buy 0.01 BTC at $60,000 with 0.00001 BTC commission
- `netQty = 0.01 − 0.00001 = 0.00999`
- `lotPrice = 60,000 × 0.01 / 0.00999 = 60,060.06`
- `lot.price × lot.remainingQuantity = 60,060.06 × 0.00999 = 600.00` ✓
- Old (wrong): `60,000 × 0.00999 = 599.40` ✗ (off by $0.60)

### 2. Lot Price Inflation (Quote-asset Commission)

```swift
let lotPrice = (trade.price × trade.quantity + trade.commission) / trade.quantity
let usdtSpent = trade.price × trade.quantity + trade.commission
```

**Example**: Buy 0.01 BTC at $60,000 with 0.01 USDT commission
- `lotPrice = (600 + 0.01) / 0.01 = 60,001.00`
- `usdtSpent = 600 + 0.01 = 600.01`

### 3. Simple Average Buy Price (Binance Display)

```
simpleAvgBuyPrice = totalBoughtUSDT / totalBoughtQuantity
```

Where:
- `totalBoughtUSDT` = sum of `usdtSpent` across **all** buy trades
- `totalBoughtQuantity` = sum of `netQty` across **all** buy trades

This never changes after sells, matching Binance exactly.

### 4. Invested USDT (Display)

```swift
let invested = avgBuyPrice × walletQuantity
```

Uses the wallet's authoritative quantity (from balances), not the FIFO
remaining quantity. This is what the Holdings tab shows as "Invested".

### 5. Unrealized P&L (Display)

```swift
let unrealizedPnL = walletQuantity × currentPrice − invested
```

### 6. Weighted Average Buy Price (FIFO, for tax/cost basis)

```
Σ(lot.price × lot.remainingQuantity) / Σ(lot.remainingQuantity)
```

This changes after sells (only remaining lots contribute). Used for
tax cost-basis calculations, not displayed to users.

---

## Dust Filtering

Small buy trades (e.g., leftover dust < 0.00001 BTC) are filtered using:

```swift
let epsilon = 1e-12
```

Only trades with `netQty > epsilon` are added to the lot list. This prevents
near-zero quantities from creating floating-point noise in the average.

---

## Source Files

| File | Role |
|---|---|
| `FIFOCalculator.swift` | Core computation: lot inflation, FIFO matching, simple avg |
| `HoldingFactory.swift` | Converts FIFOResult → Holding for the Holdings tab |
| `CoinDetailProcessor.swift` | Converts FIFOResult → Holding for the coin detail screen |
| `HoldingsProcessor.swift` | Orchestrates: fetches trades, runs FIFO, calls HoldingFactory |
