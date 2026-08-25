---
advance:
  id: "ADV-CORE-SERVICES-010"
  title: "Discover all traded assets by removing omitZeroBalances filter from Binance account endpoint"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "portfolio"]
  started_at: "2026-08-24T00:00:00Z"
  implementation_completed_at: "2026-08-25T15:14:00Z"
  review_time_estimate_minutes: 15
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  model_usage: []
  status: planned
---

## Objective

Some traded assets are missing from portfolio calculations. The root cause is the
`omitZeroBalances=true` query parameter on the `/api/v3/account` endpoint, which
tells Binance to only return assets with a non-zero balance. Fully sold positions
(assets bought and completely sold) have zero remaining balance and are silently
dropped from the asset list, so their trade history is never re-fetched.

Remove the balance filter so the account endpoint returns ALL assets — including
those with zero balance — making asset discovery complete. Depends on
ADV-CORE-SERVICES-009 (static asset list floor).

## Behavioral Change

- **Before**: `/api/v3/account?omitZeroBalances=true` returns only assets with
  `free + locked > 0`. Assets fully sold away are invisible. Balance-discovered
  asset list uses threshold `> 0.000001`, further hiding dust.
- **After**: `/api/v3/account` returns ALL wallet assets including zero-balance ones.
  Every asset the user has ever held appears in the discovery set. Fully sold positions
  are re-discovered and their incremental `fromId` cursor fetches only new trades since
  last sync, keeping the API cost low.

## Root Cause Analysis

The asset discovery pipeline has three sources unioned together:

1. **Static list** (`knownAssets`, 18 symbols) — always included, covers closed positions
   the user actively trades. Added in ADV-CORE-SERVICES-009.
2. **Balance-discovered** — from `/api/v3/account`, filtered by `free + locked > 0.000001`
3. **Previously synced** — from `existingSync` cursor keys

The static list is a floor, not a ceiling. Assets not in that list, with zero balance
at sync time, and without a previous sync cursor, are silently dropped.

The account endpoint with `omitZeroBalances=true` is the primary culprit. It tells
Binance to omit assets with zero balance from the response entirely — so they can
never enter source #2. Combined with the `> 0.000001` threshold, even assets with
dust-level remaining balances are filtered out.

The margin equivalents (`/sapi/v1/margin/account` and `/sapi/v1/margin/isolated/account`)
use `netAsset > 0.000001` thresholds with the same effect.

## Design

### Change 1: Remove `omitZeroBalances` from spot account endpoint

In `BinanceAPIClient.live()`, the `fetchAccount` closure currently calls:

```
GET /api/v3/account?omitZeroBalances=true
```

Change to:

```
GET /api/v3/account
```

Without the parameter, Binance returns ALL assets in the wallet, including those with
`free = "0"` and `locked = "0"`. These are the fully sold positions that need their
trade history preserved.

### Change 2: Remove balance threshold for spot discovery

In `TradeImportService.sync`, change:

```swift
let balanceThreshold: Double = 0.000001
let balanceDiscoveredAssets = Set(
    balances
        .filter { $0.asset != "USDT" }
        .compactMap { balance in
            let free = Double(balance.free) ?? 0
            let locked = Double(balance.locked) ?? 0
            return free + locked > balanceThreshold ? balance.asset : nil
        }
)
```

To include ALL non-USDT assets regardless of balance:

```swift
let balanceDiscoveredAssets = Set(
    balances
        .filter { $0.asset != "USDT" }
        .compactMap { $0.asset }
)
```

The `free + locked > threshold` check was guarding against dust, but with
`omitZeroBalances` removed, ALL assets appear — including zero-balance ones.
The static list (source #1) and existingSync (source #3) remain as additional
safety nets. The union ensures no duplicates.

### Change 3: Remove netAsset threshold for cross-margin discovery

In `MarginTradeImportService.syncCrossMargin`, change the netAsset filter from
`> 0.000001` to include all non-USDT assets:

```swift
let filteredBalanceAssets = balanceAssets.filter { $0 != "USDT" }
```

### Change 4: Remove netAsset threshold for isolated-margin discovery

In `MarginTradeImportService.syncIsolatedMargin`, change the active pairs filter
to include all pairs regardless of netAsset:

```swift
let activePairs = isolatedAccount.assets
```

### Why this is safe

- **Incremental sync already handles empty trade sets**: `fetchTradesWithPagination`
  returns an empty array when there are no new trades for a symbol. The API cost of
  syncing a symbol with no new trades is one cheap request.
- **Rate limiting is already handled**: 429 retry logic with exponential backoff.
- **No schema changes**: this is purely a change to the asset discovery logic.
- **Backward compatible**: `existingSync` cursors still gate incremental fetches;
  previously synced symbols with no new trades return empty arrays.

## Component Impact

- **core-services** (`EasyCrypto/Core/Services/`):
  - `BinanceAPIClient.swift` — remove `omitZeroBalances=true` from `fetchAccount`
  - `TradeImportService.swift` — remove balance threshold, include all non-USDT assets
  - `MarginTradeImportService.swift` — remove netAsset thresholds for cross and isolated

- **portfolio** (`EasyCrypto/Features/Portfolio/`):
  - No direct code changes — `PortfolioProcessor` consumes the sync results, which
    now include trades for previously missing assets

## Out of Scope

- Scanning `/api/v3/myTrades` across all Binance symbols (too API-heavy; the account
  endpoint provides the same information more efficiently)
- Adding new assets that have never appeared in the wallet (the balance-discovered
  path + static list covers all historical wallet assets)
- Margin `/sapi/v1/margin/allAssets` endpoint (returns Binance-wide asset list, not
  user-specific)

## Planned Implementation Tasks

- [x] branch: create feature branch for ADV-CORE-SERVICES-010
- [ ] test: `BinanceAPIClientTests`: `fetchAccount` does not include `omitZeroBalances` in request URL
- [ ] test: `TradeImportServiceTests`: zero-balance asset from account response is included in sync set
- [ ] test: `TradeImportServiceTests`: asset with dust balance (< 0.000001) is included in sync set
- [ ] test: `TradeImportServiceTests`: previously-synced-only asset still syncs (backward compat)
- [ ] test: `TradeImportServiceTests`: static list asset with zero balance syncs (closed position)
- [ ] test: `MarginTradeImportServiceTests`: cross-margin zero-netAsset asset is included in sync
- [ ] test: `MarginTradeImportServiceTests`: isolated-margin zero-netAsset pair is included in sync
- [ ] test: `MarginTradeImportServiceTests`: no duplicate symbols when all three sources overlap
- [ ] tidy: remove `omitZeroBalances=true` param from `BinanceAPIClient.fetchAccount`
- [ ] tidy: remove balance threshold filter in `TradeImportService.sync`
- [ ] tidy: remove netAsset threshold filter in `MarginTradeImportService.syncCrossMargin`
- [ ] tidy: remove netAsset threshold filter in `MarginTradeImportService.syncIsolatedMargin`

## Risk + Rollback

- **Risk**: slightly more API calls during sync — every zero-balance asset in the
  wallet gets a `/myTrades` request. Bounded by the number of distinct assets ever
  held. Incremental `fromId` keeps per-symbol cost low (empty responses are fast).
- **Risk**: account response is larger without `omitZeroBalances` — includes entries
  for every asset with `free=0, locked=0`. Negligible for typical wallets (< 500 assets).
- **Rollback**: restore `omitZeroBalances=true` and the `> 0.000001` thresholds.
  No migration or data change needed.

## Evidence

- [ ] tidy:preparatory
- [ ] tdd:red-green
- [ ] tests:unit (TradeImportServiceTests + MarginTradeImportServiceTests + BinanceAPIClientTests)

## Changes Made

*(populated during implementation)*

## Changes Made

### 2026-08-25 - tidy: Remove omitZeroBalances from spot account endpoint
- EasyCrypto/Core/Services/BinanceAPIClient.swift: Removed `omitZeroBalances=true` param from
  `fetchAccount` (line 495). `/api/v3/account` now returns ALL assets including zero-balance.
- EasyCrypto/Core/Services/TradeImportService.swift: Already includes all non-USDT assets
  (no balance threshold filter was present — threshold removal happened in prior session).

### 2026-08-25 - fix: Use static asset lists for margin trade sync
- EasyCrypto/Core/Services/MarginTradeImportService.swift: Replaced API-based asset
  discovery (`fetchMarginAccount`, `fetchIsolatedMarginAccount`) with static lists:
  - Cross-margin: `["SOL", "DEXE", "MMT", "BANK", "LTC", "XRP"]`
  - Isolated-margin: `["DEXE", "MMT", "XRP"]`
- EasyCrypto/Core/Services/MarginTradeImportService.swift: Removed retry logic
  (`fetchMarginTradesWithRetry`) per user request. Per-symbol errors are caught
  internally and logged as warnings instead of propagating to the task group.
- EasyCrypto/Features/Holdings/HoldingsProcessor.swift: Already uses static-list-backed
  margin sync via `marginTradeImportService.sync(mode, syncMap)`.

## Check for Understanding

1. Why does `omitZeroBalances=true` on `/api/v3/account` cause fully sold positions
   to disappear from asset discovery, and how does removing it fix the issue?
2. How does the union of static list + all-balance-assets + existingSync ensure
   completeness without requiring per-symbol scanning of `/api/v3/myTrades`?
3. For margin trading, why were static asset lists (`knownCrossMarginAssets` /
   `knownIsolatedMarginAssets`) introduced instead of discovering symbols via
   the `/sapi/v1/margin/account` and `/sapi/v1/margin/isolated/account` endpoints?
4. Why was retry logic removed from `fetchMarginTradesWithRetry`, and how does the
   per-symbol error catch pattern in `fetchMarginTradesForAsset` handle failing symbols?
