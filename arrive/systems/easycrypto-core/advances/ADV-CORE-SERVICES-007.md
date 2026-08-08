---
advance:
  id: "ADV-CORE-SERVICES-007"
  title: "Margin balance aggregation service — cross-margin overview and isolated-margin per-asset balances"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "core-models"]
  started_at: "2026-08-07T09:00:00Z"
  implementation_completed_at: ~
  review_time_estimate_minutes: 30
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  model_usage: []
  status: planned
---

## Objective

Add a `MarginBalanceService` that calls the margin API endpoints (`fetchMarginAccount`
for cross-margin, `fetchIsolatedMarginAccount` and `fetchMarginAllAssets` /
`fetchIsolatedMarginTransfers` for isolated-margin) to produce a unified balance view
— including the per-asset borrowing interest that feeds margin-adjusted P&L
(ADV-CORE-SERVICES-008) and the isolated liquidation price shown in Holdings
(ADV-PORTFOLIO-002). This service feeds the Holdings tab's margin mode
(ADV-PORTFOLIO-002) and the Settings margin overview (ADV-SETTINGS-003).
Depends on ADV-CORE-SERVICES-005 (margin API endpoints) and ADV-CORE-MODELS-002 (TradingMode).

## Behavioral Change

After this advance:

- New `MarginBalanceService` (struct-with-closures) exposes:
  - `fetchCrossMarginAccount` closure: returns `CrossMarginAccountData` (total assets,
    total liabilities, net asset, margin level, max borrow per asset, **and
    `perAssetInterest: [String: Double]` derived from the `userAssets` array — the
    data source `calculateMargin`'s `borrowingFees` input uses for cross-margin**)
  - `fetchIsolatedMarginBalances` closure: returns `[IsolatedMarginBalance]` (per-asset
    borrowed, free, locked, interest, **plus `liquidationPrice: Double?` and
    `marginLevel: Double?` sourced from `fetchIsolatedMarginAccount`**) for a given
    isolated symbol
- The service dispatches to `fetchMarginAccount`, `fetchIsolatedMarginAccount`, or
  `fetchMarginAllAssets` / `fetchIsolatedMarginTransfers` from `BinanceAPIClient` based
  on the `TradingMode`.
- Cross-margin data is a single aggregated snapshot, but now includes the per-asset
  `userAssets` breakdown needed for interest attribution (no separate call required).
- Isolated-margin data is per-isolated-symbol; the service calls `fetchIsolatedMarginAccount`
  (batched, up to 5 symbols per call per Binance's limit) for liquidation price + margin
  level, and merges it with `fetchMarginAllAssets` for borrowed/free/locked/interest.
- Preview and noop variants return empty/default data structures.
- Errors are propagated with contextual messages (e.g., "cross-margin account fetch failed").

## Design Notes

- **Cross-margin is a single call**: `/sapi/v1/margin/account` returns one JSON object
  with all cross-margin metrics, including the `userAssets` array `CrossMarginAccountData`
  maps into `perAssetInterest`. No pagination needed.
- **Isolated-margin liquidation price + margin level come from `fetchIsolatedMarginAccount`**:
  `/sapi/v1/margin/isolated/account` (ADV-CORE-SERVICES-005) is the only Binance endpoint
  that returns `liquidatePrice` per isolated pair; `fetchMarginAllAssets` alone does not.
  The service merges both responses into one `IsolatedMarginBalance` per symbol.
- **Isolated-margin requires iteration**: `/sapi/v1/margin/allAssets` returns all isolated
  margin assets in one call for borrowed/free/locked. `/sapi/v1/margin/transfer` is
  per-isolated-symbol but `allAssets` already covers the balance view, so the service uses
  it as the primary source and falls back to per-symbol transfer history only when needed.
- **No persistent model needed**: Cross-margin data is a computed snapshot (like spot
  balances via `fetchBalances`). Isolated-margin per-asset balances persist to the
  existing `MarginBalance` SwiftData model (introduced in ADV-CORE-MODELS-002); the
  fetched `liquidationPrice`/`marginLevel` are refreshed on each sync, not persisted
  (they're point-in-time risk metrics, not cost-basis data).
- **Response types**: New value types `CrossMarginAccountData` and `IsolatedMarginBalance`
  are pure structs, not `@Model`. They mirror the DTOs from the API client but expose
  domain-friendly computed properties (e.g., `netAsset`, `marginRatio`).
- **Rate limits**: `fetchMarginAllAssets` is a single endpoint call. The service batches
  per-isolated-symbol `fetchIsolatedMarginAccount` and transfer fetches with a small delay
  between calls.

## Component Impact

- **core-services** (`EasyCrypto/Core/Services/`):
  - New `MarginBalanceService.swift` — struct-with-closures with `fetchCrossMarginAccount`
    and `fetchIsolatedMarginBalances` closures
  - New `CrossMarginAccountData.swift` — value type for cross-margin snapshot
  - New `IsolatedMarginBalance.swift` — value type for isolated-margin per-asset balance

## Out of Scope

- Margin P&L calculation (ADV-CORE-SERVICES-008) — this service supplies
  `perAssetInterest`/per-asset `interest` as raw inputs; it does not deduct them from P&L
- Margin loan/repay (not planned — read-only)
- Isolated-margin interest **APR/rate** fetching (not planned — only accrued interest
  **amounts**, already covered by `fetchMarginAccount`/`fetchIsolatedMarginAccount`)
- Margin balance display in Holdings (ADV-PORTFOLIO-002)
- Background margin refresh (ADV-APP-SHELL-002)

## Planned Implementation Tasks

- [ ] test: `fetchCrossMarginAccount` DTO decodes correctly from sample JSON, and
      `perAssetInterest` is correctly derived from `userAssets`
- [ ] test: `fetchIsolatedMarginBalances` aggregates per-symbol data correctly, merging
      `fetchIsolatedMarginAccount` (`liquidationPrice`, `marginLevel`) with
      `fetchMarginAllAssets` (borrowed/free/locked/interest)
- [ ] test: preview/noop variants return empty/default data
- [ ] test: `.spot` mode throws `.invalidMode`
- [ ] tidy: add `CrossMarginAccountData` value type (incl. `perAssetInterest`)
- [ ] tidy: add `IsolatedMarginBalance` value type (incl. `liquidationPrice`, `marginLevel`)
- [ ] tidy: add `MarginBalanceService` struct with `fetchCrossMarginAccount` and
      `fetchIsolatedMarginBalances` closures
- [ ] tidy: implement `live()` dispatching to correct `BinanceAPIClient` margin closures,
      merging `fetchIsolatedMarginAccount` + `fetchMarginAllAssets` for isolated symbols

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: additive new service. No existing code path changes.
- Rollback: revert commits. No migration needed.

## Evidence

- [ ] tidy:preparatory
- [ ] tdd:red-green
- [ ] tests:unit (MarginBalanceServiceTests — target 7 tests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-SERVICES-007 --status passed`

## Changes Made

*(populated during implementation)*

## Check for Understanding

1. Why does cross-margin require only a single API call while isolated-margin requires
    iterating over symbols, and how does the service handle this asymmetry?
2. How does `MarginBalanceService` differ from `BalanceService` in terms of input
    parameters, return types, and persistence strategy?
3. Why are `CrossMarginAccountData` and `IsolatedMarginBalance` value types (structs)
    rather than `@Model` SwiftData models?
