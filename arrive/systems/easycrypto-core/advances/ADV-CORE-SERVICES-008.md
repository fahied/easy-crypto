---
advance:
  id: "ADV-CORE-SERVICES-008"
  title: "Margin-aware FIFO calculator — borrowing costs and margin-adjusted P&L"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "core-models"]
  started_at: "2026-08-07T09:00:00Z"
  implementation_completed_at: "2026-08-09T04:30:00Z"
  review_time_estimate_minutes: 30
  review_time_actual_minutes: 15
  pr_links: []
  reviewability_score: 8
  risk_flags: []
  evidence:
    - tidy:preparatory
    - tdd:red-green
    - tests:unit (MarginFIFOCalculatorTests — 9 tests passed)
  model_usage: []
  status: complete
---

## Objective

Extend `FIFOCalculator` to handle margin trades correctly: factor in borrowing fees
and interest costs that are unique to margin trading, and produce a margin-adjusted
P&L that distinguishes spot gains from margin gains. Depends on ADV-CORE-SERVICES-006
(margin trade import) and ADV-CORE-SERVICES-007 (margin balance aggregation).

## Behavioral Change

After this advance:

- `FIFOCalculator` gains a new closure `calculateMargin`:
  `(_ trades: [FIFOTrade], _ borrowingFees: [String: Double]) -> MarginFIFOResult`
- New `MarginFIFOResult` wraps the existing `FIFOResult` and adds:
  - `totalBorrowingFees: Double` — sum of all borrowing/interest costs for the asset
  - `marginAdjustedRealizedPnL: Double` — `FIFOResult.realizedPnL - totalBorrowingFees`
  - `isMarginPosition: Bool` — true when any trade in the input is a margin trade
- The existing `calculate` closure is unchanged — spot-only callers see zero difference.
- When `calculateMargin` receives only spot trades, it delegates to `calculate` and
  returns zero borrowing fees (backward-compatible behavior).
- The `saleBreakdowns` closure gains an optional `borrowingFeePerUnit: Double` parameter
  that distributes the fee across sold quantity in each breakdown.

## Design Notes

- **FIFO mechanics are identical for spot and margin**: The lot-consumption algorithm
  doesn't change. The only difference is the cost attribution — margin trades incur
  borrowing costs that must be deducted from realized P&L.
- **Borrowing fees are per-asset**: Binance reports margin interest per asset. The
  `borrowingFees` parameter is `[String: Double]` keyed by asset, matching the
  `FIFOTrade.asset` field. For cross-margin, the caller sources this from
  `CrossMarginAccountData.perAssetInterest`; for isolated-margin, from
  `IsolatedMarginBalance.interest` (both from ADV-CORE-SERVICES-007).
- **Separation of concerns**: `FIFOCalculator` computes P&L; the caller (PortfolioProcessor)
  is responsible for fetching borrowing fees from `MarginBalanceService`. This keeps
  the calculator pure and testable.
- **No breaking change**: The existing `calculate` and `saleBreakdowns` closures are
  untouched. `calculateMargin` is a new closure. All existing callers continue to work
  without modification.

## Component Impact

- **core-services** (`EasyCrypto/Core/Services/`):
  - Modify `FIFOCalculator.swift` — add `calculateMargin` closure
  - New `MarginFIFOResult.swift` — result type with margin-adjusted fields

## Out of Scope

- Margin liquidation price — fetched directly from Binance's isolated-margin account
  endpoint (`fetchIsolatedMarginAccount`, ADV-CORE-SERVICES-005/007) and surfaced via
  `IsolatedMarginBalance.liquidationPrice`; `FIFOCalculator` does not compute it
- Cross-margin vs isolated-margin P&L differentiation beyond fee attribution
- Margin leverage impact on cost basis (assumes 1x for FIFO)
- Margin UI display (ADV-DESIGN-SYSTEM-001, ADV-TRADE-HISTORY-001)

## Planned Implementation Tasks

- [ ] test: `calculateMargin` with spot-only trades returns same P&L as `calculate`
- [ ] test: `calculateMargin` subtracts borrowing fees from realized P&L
- [ ] test: `MarginFIFOResult.marginAdjustedRealizedPnL` equals `realizedPnL - totalBorrowingFees`
- [ ] test: `isMarginPosition` is true when any trade is a margin trade
- [ ] test: `saleBreakdowns` with `borrowingFeePerUnit` distributes fees correctly
- [ ] test: empty trades return empty result regardless of fees
- [ ] tidy: add `MarginFIFOResult` value type
- [ ] tidy: add `calculateMargin` closure to `FIFOCalculator`
- [ ] tidy: extend `saleBreakdowns` with optional borrowing fee parameter

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: additive new closure and type. No existing code path changes.
- Rollback: revert commits. No migration needed.

## Evidence

- [ ] tidy:preparatory
- [ ] tdd:red-green
- [ ] tests:unit (MarginFIFOCalculatorTests — target 7 tests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-SERVICES-008 --status passed`

## Changes Made

- `EasyCrypto/Core/Services/FIFOCalculator.swift` — added `MarginFIFOResult` type,
  `saleBreakdownsWithBorrowingFee` and `calculateMargin` closures to `FIFOCalculator`,
  extracted `fifoCompute`/`fifoComputeBreakdowns` as module-level shared engine
- `EasyCryptoTests/Core/Services/MarginFIFOCalculatorTests.swift` — 9 unit tests:
  fee subtraction, multi-asset fee summation, zero-fee spot parity, empty trades,
  buy-only isMarginPosition=false, formula verification, lot parity, breakdown fees,
  zero-fee breakdown parity

## Check for Understanding

1. Why does the FIFO calculation algorithm itself not need to change for margin trades,
    and what aspect of margin trading requires the new `calculateMargin` closure?
2. How does the separation between `FIFOCalculator` (pure computation) and
    `MarginBalanceService` (API data fetching) support testability?
3. Why is `calculateMargin` a new closure rather than modifying the existing `calculate`
    closure's signature?
