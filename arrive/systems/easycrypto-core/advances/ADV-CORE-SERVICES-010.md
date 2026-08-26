---
advance:
  id: "ADV-CORE-SERVICES-010"
  title: "Fix FIFO weighted avg buy price understated by base-asset commission"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "core-models"]
  started_at: "2026-08-26T00:00:00Z"
  implementation_completed_at: ~
  review_time_estimate_minutes: 15
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: ~
  risk_flags: []
  evidence: []
  status: planned
---

## Objective

The "Avg Buy" value shown on the Holdings tab is systematically lower than the true cost
basis. This happens when the Binance API reports commission paid in the **base asset** on a
buy trade (e.g., BTC commission on a BTC/USDT buy). The FIFO calculator reduces the lot
quantity by the commission amount but keeps the per-unit price at `trade.price`, effectively
losing the USD value of the commission from the cost basis.

## Root Cause

In `FIFOCalculator.fifoCompute()`, buy-side base-asset commission handling:

```swift
if trade.commissionAsset == trade.asset {
    qty -= trade.commission          // net quantity after commission
}
lots.append(BuyLot(price: trade.price, remainingQuantity: qty))
```

`trade.price` is the per-unit price of the **original** `trade.quantity`, but
`remainingQuantity` is the **net received** after commission. So the lot's total cost
contribution is `trade.price * (quantity - commission)`, which excludes the USD value of
the commission.

The weighted average computes:
```
totalInvested = Σ(lot.price * lot.remainingQuantity) = trade.price * (quantity - commission)
totalRemainingQty = Σ(lot.remainingQuantity) = quantity - commission
weightedAvg = trade.price * (quantity - commission) / (quantity - commission) = trade.price
```

This equals `trade.price`, not the true effective price of
`trade.price * quantity / (quantity - commission)`.

**Sell side is correct**: the fee is subtracted from realized P&L at lines 108-109:
`realizedPnL -= feePortion * lots[0].price` — this accounts for commission's cost impact on
the realized side, but the buy-side lot price is still wrong.

## Fix

Inflate the lot price to account for the commission's USD cost:

```swift
if trade.commissionAsset == trade.asset {
    qty -= trade.commission
    if qty > epsilon {
        let effectivePrice = trade.price * trade.quantity / qty  // includes commission cost
        lots.append(BuyLot(price: effectivePrice, remainingQuantity: qty))
    }
} else if qty > epsilon {
    lots.append(BuyLot(price: trade.price, remainingQuantity: qty))
}
```

Now `lot.price * lot.remainingQuantity = trade.price * trade.quantity`, which correctly
includes the commission's USD cost. The weighted average divides by the net quantity to
give the true effective per-unit cost basis.

## Behavioral Change

- **Before**: Buy trades with base-asset commission show weighted avg buy price =
  `trade.price` (understates true cost by ~0.1% per trade, compounds over many buys).
- **After**: Weighted avg buy price correctly includes commission cost:
  `trade.price * trade.quantity / (trade.quantity - commission)`.

## Implementation Tasks

### tidy
- None — fix is a localized change to one line.

### test
- [ ] `FIFOCalculatorTests`: buy with base-asset commission → weighted avg buy price is
      inflated above `trade.price`
- [ ] `FIFOCalculatorTests`: buy with base-asset commission after sells → avg reflects
      inflated cost basis
- [ ] `FIFOCalculatorTests`: buy with quote-asset commission (USDT) → no change, price
      stays at `trade.price` (control case)
- [ ] `FIFOCalculatorTests`: buy with no commission → no change (control case)
- [ ] `PortfolioProcessorTests`: portfolio invested assets computation uses corrected
      FIFO results

### feat
- [ ] `FIFOCalculator.fifoCompute()`: inflate lot price when buy-side commission is in
      base asset (line 95 change)

## Risk + Rollback

- **Risk**: existing tests may assert the old (wrong) price. Must update any assertions
  that depend on the old behavior.
- **Risk**: the fix changes `weightedAvgBuyPrice` for any position that has ever had a
  buy-side base-asset commission. Holdings views and portfolio calculations that consume
  this value will reflect the corrected cost basis.
- **Rollback**: revert the one-line change in `fifoCompute()`. The old behavior is
  isolated to lot price computation; no schema changes are involved.

## Dependencies

- Blocked by: none.
- Blocks: none.

## Check for Understanding

1. Why does base-asset commission on a buy trade cause the weighted avg buy price to be
   understated, and why does quote-asset commission not have this problem?
2. Why is the sell-side commission handling already correct (subtracting from realized P&L)
   while the buy-side handling was wrong?
3. What does the fix ensure about `lot.price * lot.remainingQuantity` relative to the
   total USD spent on the buy?
