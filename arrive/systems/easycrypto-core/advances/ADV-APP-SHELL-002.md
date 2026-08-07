---
advance:
  id: "ADV-APP-SHELL-002"
  title: "Background margin refresh — margin balance sync and margin price alerts"
  system: "easycrypto-core"
  primary_component: "app-shell"
  components: ["app-shell", "core-services", "core-models"]
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

Add a background refresh path for margin data: periodically sync margin trades and
margin balances so the Holdings and Trade History tabs show fresh margin data even
when the app is in the background. Also extend the price-alert refresher to evaluate
margin positions. Depends on ADV-CORE-SERVICES-006 (margin trade import),
ADV-CORE-SERVICES-007 (margin balance service), and ADV-APP-SHELL-001 (existing BG task).

## Behavioral Change

After this advance:

- `EasyCryptoApp` registers a second `BGAppRefreshTask` identifier
  (`com.fahied.EasyCrypto.marginRefresh`) alongside the existing price-alert task.
- On margin refresh wake: the app checks the user's selected `TradingMode`. If it's
  `.crossMargin` or `.isolatedMargin`, it runs:
  1. `MarginTradeImportService.sync` to fetch new margin trades
  2. `MarginBalanceService.fetchCrossMarginAccount` or `fetchIsolatedMarginBalances`
     to update balance snapshots
- If the selected mode is `.spot`, the margin refresh task exits early (no work needed).
- The existing price-alert refresher (`PriceAlertRefresher`) is extended to evaluate
  alerts against margin holdings when the mode is margin — it loads margin trades,
  computes margin-adjusted P&L, and fires alerts for margin-specific thresholds
  (e.g., margin level drop, borrowing fee spike).
- Both BG tasks are rescheduled independently on each wake and on `scenePhase`
  background transitions.
- `Info.plist` gains the new `BGTaskSchedulerPermittedIdentifiers` entry.
- On margin API failure during background refresh, the task logs the error and
  reschedules — it does not crash or block the next wake.

## Design Notes

- **Two independent BG tasks**: The existing `PriceAlertRefresher` and the new
  `MarginRefresher` run on separate identifiers. This lets the OS schedule them
  independently and prevents a margin API slowdown from delaying alert evaluation.
- **Mode-gated execution**: Both tasks check the persisted `selectedTradingMode`
  before doing work. In spot mode, margin refresh is a no-op; price alerts evaluate
  spot-only P&L. This avoids unnecessary API calls.
- **Margin alert types**: New alert directions are deferred to a future advance
  (margin liquidation risk, borrowing fee spikes). This advance adds the plumbing
  only — the existing alert types (gain, loss, priceUp, priceDown, candleDrop) work
  for margin positions with margin-adjusted P&L.
- **Error resilience**: Background tasks must always call `setTaskCompleted` or the
  OS will stop scheduling them. The margin refresher wraps all work in do/catch,
  logs errors, and always completes the task.
- **Task cadence**: Both tasks use `earliestBeginDate` of ~5 minutes. The OS may
  coalesce them.

## Component Impact

- **app-shell** (`EasyCrypto/EasyCryptoApp.swift`):
  - Register second BG task identifier + handler
  - Add `MarginRefresher` runner (testable, mirrors `PriceAlertRefresher` pattern)
  - Reschedule both tasks on `scenePhase` background

- **BackgroundTasks** (`EasyCrypto/BackgroundTasks/`):
  - New `MarginRefresher.swift` — testable runner for margin sync

- **core-services** (`EasyCrypto/Core/Services/`):
  - Extend `PriceAlertRefresher` to accept optional `TradingMode` and use margin
    P&L when appropriate

## Out of Scope

- Margin liquidation push notifications (separate advance)
- Margin balance sync during foreground (handled by PortfolioProcessor)
- Margin-specific alert types (liquidation risk, fee spike — deferred)
- Background sync for isolated-margin symbol discovery

## Planned Implementation Tasks

- [ ] test: margin refresh exits early when mode is `.spot`
- [ ] test: margin refresh calls `MarginTradeImportService` and `MarginBalanceService`
       when mode is margin
- [ ] test: margin refresh completes task on API failure (no crash)
- [ ] test: price alert refresher uses margin P&L when mode is margin
- [ ] test: both BG tasks reschedule independently
- [ ] tidy: add `MarginRefresher.swift` (testable runner)
- [ ] tidy: register `marginRefresh` task identifier in `EasyCryptoApp`
- [ ] tidy: extend `PriceAlertRefresher` with optional `TradingMode`
- [ ] tidy: add `BGTaskSchedulerPermittedIdentifiers` entry to Info.plist

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: adds a second BG task. Both tasks are additive — removing one does not affect
  the other. Margin refresh is mode-gated, so spot-only users never trigger it.
- Rollback: revert commits. Remove task registration and `MarginRefresher`. No data
  migration.

## Evidence

- [ ] tidy:preparatory
- [ ] tdd:red-green
- [ ] tests:unit (MarginRefresherTests — target 5 tests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-APP-SHELL-002 --status passed`

## Changes Made

*(populated during implementation)*

## Check for Understanding

1. Why are there two independent `BGAppRefreshTask` identifiers instead of a single
    task that handles both price alerts and margin refresh?
2. How does the margin refresher avoid making unnecessary API calls when the user is
    in spot mode?
3. Why must the margin refresher always call `setTaskCompleted` even on failure, and
    what would happen if it didn't?
