---
advance:
  id: "ADV-CORE-SERVICES-011"
  title: "Parallelize trade sync and holdings computation to reduce load time"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "holdings", "portfolio"]
  started_at: "2026-08-25T00:00:00Z"
  implementation_completed_at: ~
  review_time_estimate_minutes: 30
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 28
  risk_flags: ["concurrency-semantics", "api-throttling"]
  evidence: []
  model_usage: []
  status: planned
---

## Objective

The Holdings and Portfolio tabs take 8–15+ seconds to load because every trade-sync
path processes assets sequentially, and holdings computation runs sequentially within
each trading mode. This advance replaces the serial `for`-loop + `Task.sleep(300ms)`
pattern with concurrent `TaskGroup` fetching, parallelizes per-asset FIFO computation,
and deduplicates redundant API calls. The result should bring a full refresh from
~12s to under 4s on a typical 18-asset portfolio.

## Root Cause Analysis

Four bottlenecks compound to make the Holdings/Portfolio tabs slow:

### 1. Sequential per-asset HTTP fetching (primary bottleneck)

**TradeImportService.sync** ([TradeImportService.swift:114-160](EasyCrypto/Core/Services/TradeImportService.swift#L114-L160)):
Iterates over all discovered assets with `for (index, asset) in assets.enumerated()`.
Each iteration calls `fetchTradesWithRetry` (one HTTP round-trip per symbol), then
sleeps 300ms before the next. With 18 assets and ~200ms network latency per call,
this alone is ~9 seconds: `18 × (200ms + 300ms) = 9s`.

**MarginTradeImportService.syncCrossMargin** ([MarginTradeImportService.swift:105-151](EasyCrypto/Core/Services/MarginTradeImportService.swift#L105-L151)):
Identical sequential pattern for cross-margin symbols.

**MarginTradeImportService.syncIsolatedMargin** ([MarginTradeImportService.swift:211-258](EasyCrypto/Core/Services/MarginTradeImportService.swift#L211-L258)):
Identical sequential pattern for isolated-margin symbols.

### 2. Sequential FIFO computation per asset

**HoldingsProcessor.loadMarginHoldings** ([HoldingsProcessor.swift:151-164](EasyCrypto/Features/Holdings/HoldingsProcessor.swift#L151-L164)):
Two sequential `for`-loops over `tradesByAsset` — one for FIFO, one for margin-adjusted
P&L. Each asset's FIFO calculation is synchronous and independent.

**HoldingsProcessor.computeFIFO** ([HoldingsProcessor.swift:273-281](EasyCrypto/Features/Holdings/HoldingsProcessor.swift#L273-L281)):
Uses `uniqueKeysWithValues` with per-asset sequential calculation.

### 3. Sequential holdings sub-computation

**PortfolioProcessor.computeSummary** ([PortfolioProcessor.swift:114-116](EasyCrypto/Features/Portfolio/PortfolioProcessor.swift#L114-L116)):
Calls `computeSpotHoldings()`, `computeCrossMarginHoldings()`, `computeIsolatedMarginHoldings()`
**sequentially**. Each independently fetches balances and prices. With `async let`
the three could overlap since they have no data dependency.

**HoldingsProcessor.loadAggregatedHoldings** ([HoldingsProcessor.swift:84-91](EasyCrypto/Features/Holdings/HoldingsProcessor.swift#L84-L91)):
Same pattern — three sequential mode loads when showing all holdings.

### 4. Redundant API calls

**PortfolioProcessor.refresh** calls `marginBalanceService.fetchCrossMarginBalances()`
twice — once directly at [line 96](EasyCrypto/Features/Portfolio/PortfolioProcessor.swift#L96) and once via
`persistCrossMarginBalances()` at [line 378](EasyCrypto/Features/Portfolio/PortfolioProcessor.swift#L378).
Same for isolated at [lines 100 and 392](EasyCrypto/Features/Portfolio/PortfolioProcessor.swift#L100).

**HoldingsProcessor.loadMarginHoldings** calls `marginTradeImportService.sync(mode, syncMap)`
which internally calls `apiClient.fetchMarginAccount()` / `fetchIsolatedMarginAccount([])`,
and then the Holdings tab calls `fetchAllIsolatedMarginBalancesLive()` again at
[line 140](EasyCrypto/Features/Holdings/HoldingsProcessor.swift#L140) to persist balances.

## Behavioral Change

- **Spot trade sync** drops from ~9s to ~2s: 18 assets fetched concurrently with a
  semaphore limit of 4 instead of one-at-a-time with 300ms delay.
- **Margin trade sync** (cross + isolated) drops similarly: each mode's assets fan out
  concurrently, cross and isolated modes are already parallelized via `async let`.
- **Holdings computation** drops from sequential per-asset FIFO to concurrent via
  `withThrowingTaskGroup`: FIFO is CPU-bound but each asset is independent.
- **Portfolio summary** computes spot, cross-margin, and isolated-margin holdings
  concurrently via `async let` instead of sequentially.
- **Duplicate API calls eliminated**: `fetchCrossMarginBalances` and
  `fetchAllIsolatedMarginBalances` results are reused within a single refresh cycle.

## Design

### Strategy A: Concurrent trade fetching with semaphore

Replace the `for`-loop + `Task.sleep(300ms)` in `TradeImportService.sync`,
`MarginTradeImportService.syncCrossMargin`, and `MarginTradeImportService.syncIsolatedMargin`
with `withThrowingTaskGroup` + a `Semaphore` limiting concurrency to 4 simultaneous
HTTP requests. The 300ms delay becomes the semaphore capacity — not a fixed delay
between every request.

**Why semaphore, not bare TaskGroup**: Binance imposes a rate limit. A semaphore of
4 ensures we never exceed that, while a bare `TaskGroup` could fan out all 18
requests simultaneously and trigger 429s.

**Per-symbol result ordering**: Results are collected in a dictionary keyed by symbol,
then sorted by `lastTradeId` to produce `syncUpdates` in deterministic order. The
`mappedTrades` array is order-independent.

### Strategy B: Concurrent FIFO computation

Replace the sequential `for (asset, assetTrades) in tradesByAsset` loops in
`HoldingsProcessor` with `withThrowingTaskGroup`. Each asset's FIFO calculation
is a synchronous pure function (`fifoCalculator.calculate`) — wrapping it in a
`Task` offloads it to a background thread without blocking the main actor.

### Strategy C: Parallel holdings sub-computations

In `PortfolioProcessor.computeSummary()`, replace the three sequential calls with
`async let`:

```swift
async let spotHoldings = computeSpotHoldings()
async let crossHoldings = computeCrossMarginHoldings()
async let isolatedHoldings = computeIsolatedMarginHoldings()
```

The three modes fetch different APIs and have no data dependency. With `async let`,
all three start immediately and the results are gathered at the end.

In `HoldingsProcessor.loadAggregatedHoldings()`, same pattern — three `async let`
calls for the mode-specific loads.

### Strategy D: Eliminate redundant API calls

- `PortfolioProcessor.persistCrossMarginBalances()` already calls
  `marginBalanceService.fetchCrossMarginBalances()` internally — don't also call it
  in `refresh()` before the persist.
- `HoldingsProcessor.loadMarginHoldings()` for isolated mode: the `syncFromExchange`
  path already fetches isolated balances via `marginTradeImportService.sync` which
  internally discovers pairs. The extra `fetchAllIsolatedMarginBalancesLive()` call
  at [line 140](EasyCrypto/Features/Holdings/HoldingsProcessor.swift#L140) is redundant when `syncFromExchange` is true.

## Component Impact

- **core-services** (`EasyCrypto/Core/Services/`):
  - `TradeImportService.swift` — replace sequential `for`-loop with `withThrowingTaskGroup` + `Semaphore(4)`
  - `MarginTradeImportService.swift` — same transformation for both `syncCrossMargin` and `syncIsolatedMargin`

- **holdings** (`EasyCrypto/Features/Holdings/`):
  - `HoldingsProcessor.swift` — parallelize FIFO loops with `withThrowingTaskGroup`;
    parallelize `loadAggregatedHoldings` with `async let`; remove redundant balance fetch

- **portfolio** (`EasyCrypto/Features/Portfolio/`):
  - `PortfolioProcessor.swift` — parallelize `computeSummary` sub-computations with `async let`;
    remove redundant cross-margin balance fetch

## Out of Scope

- WebSocket-based real-time price updates (separate architecture decision)
- Background sync via `BGTaskScheduler` (separate advance)
- Caching HTTP responses in memory (future optimization if needed)
- Per-symbol request cancellation on user-initiated abort

## Planned Implementation Tasks

- [ ] branch: create feature branch for ADV-CORE-SERVICES-011
- [ ] test: TradeImportService sync completes with 18 assets in under 5s (concurrent)
- [ ] test: TradeImportService sync still returns correct results when some symbols 429
- [ ] test: TradeImportService sync handles partial failures (some assets fail, others succeed)
- [ ] test: TradeImportService sync produces deterministic syncUpdates sorted by lastTradeId
- [ ] test: MarginTradeImportService cross-margin sync uses concurrency
- [ ] test: MarginTradeImportService isolated-margin sync uses concurrency
- [ ] test: HoldingsProcessor FIFO computation produces same results with concurrency
- [ ] test: HoldingsProcessor loadAggregatedHoldings fetches modes in parallel
- [ ] test: PortfolioProcessor computeSummary sub-computations run in parallel
- [ ] test: PortfolioProcessor refresh does not double-fetch cross-margin balances
- [ ] tidy: extract concurrent-fetch helper (reusable by spot and margin services)
- [ ] feat: TradeImportService.sync uses withThrowingTaskGroup + Semaphore
- [ ] feat: MarginTradeImportService.syncCrossMargin uses withThrowingTaskGroup + Semaphore
- [ ] feat: MarginTradeImportService.syncIsolatedMargin uses withThrowingTaskGroup + Semaphore
- [ ] feat: HoldingsProcessor FIFO loops use withThrowingTaskGroup
- [ ] feat: PortfolioProcessor.computeSummary uses async let for sub-computations
- [ ] feat: HoldingsProcessor.loadAggregatedHoldings uses async let
- [ ] fix: remove redundant balance fetch in PortfolioProcessor.refresh
- [ ] fix: remove redundant isolated balance fetch in HoldingsProcessor

## Risk + Rollback

- **Risk**: concurrent HTTP requests may hit Binance rate limits harder than the
  300ms delay. Mitigated by the `Semaphore(4)` cap — maximum 4 simultaneous requests,
  which is well within Binance's typical rate limit of 1200 requests/minute for
  signed endpoints. The 429 retry logic (3 retries with backoff) remains intact.
- **Risk**: concurrent FIFO computation on a background thread pool could cause
  thread contention if the user has hundreds of assets. Mitigated by the small
  number of tasks (one per asset, typically < 30) — each is microseconds of CPU work.
- **Risk**: result ordering changes — `syncUpdates` must remain sorted by `lastTradeId`
  for deterministic cursor updates. Mitigated by collecting results in a dictionary
  and sorting before producing the output array.
- **Rollback**: revert commits. The public API of `TradeImportService`, `MarginTradeImportService`,
  `HoldingsProcessor`, and `PortfolioProcessor` does not change — only internal
  concurrency strategy changes. No migration or schema change needed.

## Evidence

- [ ] tidy:preparatory — extract concurrent-fetch helper
- [ ] tdd:red-green — tests written first, implementation makes them pass
- [ ] tests:unit — TradeImportServiceTests, MarginTradeImportServiceTests, HoldingsProcessorTests, PortfolioProcessorTests
- [ ] build: succeeded
- [ ] performance: manual timing validation on device or simulator

## Check for Understanding

1. Why is a `Semaphore(4)` preferred over a bare `TaskGroup` for concurrent trade fetching,
   and what Binance rate limit does it protect against?
2. How does replacing the sequential `for`-loop with `withThrowingTaskGroup` preserve
   per-symbol error handling (continue-on-failure) semantics?
3. Why does `PortfolioProcessor.computeSummary()` benefit from `async let` parallelism
   when each sub-computation independently fetches its own balances and prices?
4. How does eliminating the duplicate `fetchCrossMarginBalances` call in
   `PortfolioProcessor.refresh()` reduce API calls without changing the persisted data?
