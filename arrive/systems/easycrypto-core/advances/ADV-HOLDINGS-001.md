---
advance:
  id: "ADV-HOLDINGS-001"
  title: "Fix Holdings tab average cost basis for assets with multiple buy orders"
  system: "easycrypto-core"
  primary_component: "holdings"
  components: ["holdings", "core-services", "portfolio"]
  started_at: "2026-08-15T00:00:00Z"
  implementation_completed_at: "2026-08-15"
  review_time_estimate_minutes: 20
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 25
  risk_flags: []
  evidence: []
  model_usage: []
  status: completed
---

## Objective

When an asset has multiple buy orders at different prices, the Holdings tab displays an
incorrect average cost basis (`weightedAvgBuyPrice`) and derived values (`totalInvestedUSDT`,
`unrealizedPnL`, `unrealizedPnLPercent`). The FIFO engine computes `weightedAvgBuyPrice` as
`totalInvested / totalRemainingQuantity` across surviving lots, but `HoldingFactory` then
applies this average to the **wallet quantity** (from the balance API) rather than the
FIFO remaining quantity. When these two quantities diverge — which happens with commissions
paid in the base asset during sells, external transfers, staking rewards, or dust operations —
the displayed invested amount and unrealized P&L become incorrect.

This advance fixes the cost basis computation so that `totalInvestedUSDT` reflects the actual
cost of the holdings the wallet reports, and ensures the Holdings tab aggregate P&L is correct
regardless of how many orders the user placed.

## Behavioral Change

After this advance:

- `totalInvestedUSDT` for each holding correctly reflects the cost basis of the wallet-reported
  quantity, even when multiple buy orders at different prices exist.
- `weightedAvgBuyPrice` correctly reflects the FIFO-weighted average of remaining lots, applied
  to the actual held quantity.
- The Holdings tab profit summary shows the **total** unrealized P&L across all positions
  (profitable and unprofitable), not just positions with gains >= $1.
- The Holdings tab profit summary card shows the count of **all** holdings, not just profitable ones.
- A "Total P&L" row or indicator distinguishes between unrealized and realized P&L at the
  holdings level, so users can see the complete picture per asset.
- Users with multiple buy orders for the same asset see a correct average cost that matches
  their actual investment in the currently held quantity.
- Spot-only users see no regression — the fix preserves existing behavior for single-order assets.

## Design Notes

- **Root cause**: `HoldingFactory.make()` computes `invested = avgBuyPrice × wallet_quantity`.
  The `avgBuyPrice` comes from FIFO's `totalInvested / totalRemainingQuantity`. When
  `wallet_quantity ≠ totalRemainingQuantity`, the invested amount is wrong. This divergence
  happens because:
  1. **Base-asset commissions on sells**: Binance deducts the commission from the asset
     balance, but the FIFO engine tracks commission as a fee portion consumed from lots,
     which can make `totalRemainingQuantity` differ from the wallet balance by the
     cumulative commission amount.
  2. **External transfers**: Transfers in/out change the wallet balance without appearing
     in trade history, so FIFO lots don't reflect them.
  3. **Staking/airdrop/dust**: Assets received without a buy trade have no FIFO cost basis.

- **Fix strategy**: Instead of relying solely on FIFO's `totalInvested / totalRemainingQuantity`,
  compute `totalInvestedUSDT` directly from the FIFO result's `totalInvested` field (which
  already accounts for commissions correctly) rather than re-deriving it as `avgBuyPrice × quantity`.
  When the FIFO has no cost basis (zero `totalInvested`), treat invested as 0 (airdrops, rewards).

- **FIFO `totalInvested` correctness**: The FIFO engine already computes `totalInvested` as
  `Σ(lot.price × lot.remainingQuantity)` for remaining lots. This represents the actual
  cost basis of the lots that survived all sells, correctly accounting for commissions
  deducted during buy and sell operations. The fix uses this value directly.

- **Profit summary fix**: Change `HoldingsState.profitableHoldings` to include all holdings
  (remove the `unrealizedPnL >= 1` filter) and compute `totalUnrealizedProfit` across all
  holdings. Add a separate `profitableHoldings` filter for the chip display, but the total
  should reflect the complete picture.

- **Realized P&L in Holdings**: Each `Holding` already carries `realizedPnL` from the FIFO
  result. The Holdings tab should surface this per-asset so users can see both realized
  and unrealized P&L for each position.

## Component Impact

- **holdings** (`EasyCrypto/Features/Holdings/`):
  - `HoldingFactory.swift` — use `fifo.totalInvestedUSDT` directly instead of deriving
    `avgBuyPrice × quantity`; add `hasCostBasis` guard
  - `HoldingsState.swift` — `profitableHoldings` returns all holdings (remove dust filter);
    add `totalPnL` combining unrealized + realized
  - `HoldingsView.swift` — profit summary card shows total across all holdings; per-asset
    chips show both unrealized and realized P&L

- **core-services** (`EasyCrypto/Core/Services/`):
  - `FIFOCalculator.swift` — add test coverage for multi-order scenarios with commissions;
    verify `totalInvested` matches expected cost basis after partial sells

- **portfolio** (`EasyCrypto/Features/Portfolio/`):
  - No changes needed — `PortfolioProcessor` already uses `totalInvestedUSDT` from each
    `Holding`, so fixing `HoldingFactory` propagates correctly.

## Out of Scope

- Per-lot cost basis drill-down (showing individual buy orders in the Holdings tab)
- Transfer detection and reconciliation (out-of-band movements)
- Staking reward cost basis (zero-cost acquisition)
- Portfolio-level P&L trends or charts
- Export to CSV

## Planned Implementation Tasks

- [ ] branch: create feature branch for this advance
- [ ] test: FIFO weighted average with 2+ buy orders at different prices (no sells)
- [ ] test: FIFO weighted average with multiple buys followed by partial sell
- [ ] test: FIFO weighted average with base-asset commission on sell (divergence case)
- [ ] test: FIFO totalInvested matches expected cost basis across 3+ orders with interleaved sells
- [ ] test: HoldingFactory.make uses fifo.totalInvestedUSDT when wallet quantity matches FIFO remaining
- [ ] test: HoldingFactory.make handles zero cost basis (airdrop/reward) correctly
- [ ] test: HoldingsState totalUnrealizedProfit sums across all holdings (remove dust filter)
- [ ] tidy: update HoldingFactory to use fifo.totalInvestedUSDT directly
- [ ] tidy: update HoldingsState to include all holdings in profit summary
- [ ] feat: add realized PnL display in Holdings tab per asset
- [ ] fix: ensure FIFO totalInvested is used as the authoritative cost basis

## Bug Fixes

- [ ] FIFO weighted average applied to wallet quantity instead of FIFO remaining quantity
  causes incorrect `totalInvestedUSDT` and `unrealizedPnL` when multiple buy orders exist
- [ ] Holdings tab profit summary excludes losing positions, showing incomplete P&L total

## Risk + Rollback

- Risk: changing `totalInvestedUSDT` computation may shift displayed values for existing users.
  The new value is more accurate (matches FIFO's own `totalInvested`), but users may see
  their "Invested" amount change after the fix.
- Risk: removing the `unrealizedPnL >= 1` filter from the profit summary may change the
  displayed "IN PROFIT" count and total for users with small losses or dust positions.
- Rollback: revert commits. No migration needed — changes are purely computational.

## Changes Made

- **`HoldingFactory.make()`** — uses `fifo.totalInvestedUSDT` directly as the authoritative
  cost basis instead of deriving `avgBuyPrice × wallet_quantity`. When `fifo.totalInvestedUSDT > 0`
  and `quantity > 0`, computes `avgBuyPrice = invested / quantity` so unrealized P&L is
  internally consistent. When no cost basis exists, sets invested=0 and unrealizedPnL=0.
- **`HoldingsState.profitableHoldings`** — returns all holdings sorted by unrealized P&L percent
  (removed the `unrealizedPnL >= 1` dust filter that excluded losing positions).
- **`HoldingsState.totalUnrealizedProfit`** — sums across all holdings directly (no longer
  delegates to `profitableHoldings`).
- **`HoldingsListView`** — changed header from "IN PROFIT" to "TOTAL P&L", chips are now
  loss-aware (red for losses, green for gains), shows realized P&L per asset when non-zero,
  and displays total holding count instead of "X of Y".
- **New test files**: `FIFOCalculatorMultiOrderTests.swift`, `HoldingFactoryTests.swift`,
  `HoldingsStateTests.swift` (23 tests total, all passing).

## Evidence

- [x] tidy:preparatory — pre-existing `fifoCompute` and `HoldingFactory` clean
- [x] tdd:red-green — all 23 tests pass, build succeeds
- [x] tests:unit — `FIFOCalculatorMultiOrderTests`, `HoldingFactoryTests`, `HoldingsStateTests`
- [x] build: succeeded

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-HOLDINGS-001 --status passed`

## Changes Made

*(filled during implementation)*

## Check for Understanding

1. Why does `HoldingFactory.make()` produce incorrect `totalInvestedUSDT` when the wallet
   quantity differs from the FIFO remaining quantity, and how does using `fifo.totalInvestedUSDT`
   directly fix this?
2. How does the FIFO engine account for base-asset commissions during sells, and why can
   this cause `totalRemainingQuantity` to diverge from the wallet balance?
3. Why does the profit summary's `unrealizedPnL >= 1` filter produce an incomplete P&L
   total, and what does including all holdings change for the user?
4. How does fixing `HoldingFactory` propagate correct values to the Portfolio tab without
   requiring changes to `PortfolioProcessor`?
