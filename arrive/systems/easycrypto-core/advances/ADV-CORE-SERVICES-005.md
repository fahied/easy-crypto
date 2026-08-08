---
advance:
  id: ADV-CORE-SERVICES-005
  title: Add Binance margin REST API endpoints to BinanceAPIClient
  system: easycrypto-core
  primary_component: core-services
  components:
  - core-services
  started_at: 2026-08-07T09:00:00Z
  started_by: null
  implementation_completed_at: 2026-08-08T03:25:08.913178Z
  implementation_completed_by: null
  updated_by: null
  archived_at: null
  archived_by: null
  review_time_estimate_minutes: 30
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  status: planned
---

## Objective

Extend `BinanceAPIClient` with the Binance margin REST API endpoints required to
fetch cross-margin and isolated-margin data: account overview (cross and per-symbol
isolated, including isolated liquidation price), margin trades, margin open orders,
all margin assets, and isolated-symbol transfer history.
Depends on ADV-CORE-MODELS-002 (TradingMode enum).

## Behavioral Change

After this advance:

- `BinanceAPIClient` exposes new closure properties:
  - `fetchMarginAccount` — `GET /sapi/v1/margin/account` (cross-margin account overview:
    margin level, total asset/liability, net asset, max borrow per asset, **and a
    per-asset `userAssets` breakdown — borrowed, free, locked, interest — which is the
    data source for cross-margin borrowing-fee attribution in ADV-CORE-SERVICES-007/008**)
  - `fetchIsolatedMarginAccount` — `GET /sapi/v1/margin/isolated/account` (per-isolated-symbol
    account: `liquidatePrice`, margin level, total asset/liability, and per-asset
    borrowed/free/locked/interest for the base and quote asset of the isolated pair —
    **this is the source of the `liquidationPrice` field consumed by ADV-PORTFOLIO-002 /
    ADV-DESIGN-SYSTEM-001**)
  - `fetchMarginMyTrades` — `GET /sapi/v1/margin/myTrades` (margin trade history with
    `isIsolated` flag per trade)
  - `fetchMarginOpenOrders` — `GET /sapi/v1/margin/openOrders` (open margin orders;
    supports `isIsolated` query param)
  - `fetchMarginAllAssets` — `GET /sapi/v1/margin/allAssets` (all margin assets with
    borrowed/free/locked quantities)
  - `fetchIsolatedMarginTransfers` — `GET /sapi/v1/margin/transfer` (isolated-margin
    transfer history for a specific isolated symbol)
- Each closure accepts a `TradingMode` parameter (`.crossMargin` or `.isolatedMargin`);
  `.spot` throws `.invalidMode` — spot endpoints are accessed via the existing closures.
- Response DTOs added: `BinanceMarginAccount`, `BinanceIsolatedMarginAccount`,
  `BinanceMarginAsset`, `BinanceMarginTrade`, `BinanceMarginOrder`, `BinanceMarginTransfer`.
- The `live()` implementation populates the new closures. `preview` and `noop` variants
  return empty data for margin closures.

## Planned Implementation Tasks

- [ ] test: `fetchMarginAccount` DTO decodes correctly from sample JSON, including
      per-asset `userAssets` (borrowed/free/locked/interest)
- [ ] test: `fetchIsolatedMarginAccount` DTO decodes correctly, including `liquidatePrice`
      per isolated symbol
- [ ] test: `fetchMarginMyTrades` with `isIsolated=true/false` returns correct data
- [ ] test: `fetchMarginAllAssets` decodes asset list with borrowed/free/locked
- [ ] test: calling margin closure with `.spot` throws `.invalidMode`
- [ ] test: preview/noop variants return empty data for all margin closures
- [ ] tidy: add `BinanceMarginAccount`, `BinanceIsolatedMarginAccount`, `BinanceMarginAsset`,
      `BinanceMarginTrade`, `BinanceMarginOrder`, `BinanceMarginTransfer` DTOs
- [ ] tidy: add `fetchMarginAccount`, `fetchIsolatedMarginAccount`, `fetchMarginMyTrades`,
      `fetchMarginOpenOrders`, `fetchMarginAllAssets`, `fetchIsolatedMarginTransfers` to
      `BinanceAPIClient`
- [ ] tidy: populate new closures in `live()` with correct `/sapi/v1/margin/*` paths

## Check for Understanding

1. Why do margin endpoints use `/sapi/v1/` while spot endpoints use `/api/v3/`,
    and how does the existing `BinanceURLBuilder` accommodate both?
2. What does the `isIsolated` query parameter do on shared margin endpoints, and how
    does the closure API expose it?
3. Why does this advance add new closures rather than extending existing ones like
    `fetchMyTrades`?
4. Why is `fetchIsolatedMarginAccount` a separate closure from `fetchMarginAccount`
    rather than one endpoint handling both cross and isolated, and which downstream
    field (consumed by ADV-CORE-SERVICES-007/008 and ADV-PORTFOLIO-002) depends on it?

## Risk + Rollback

- Risk: additive new closures + DTOs only. No existing code path changes.
- Rollback: revert commits. No migration or data change needed.

## Evidence

- [ ] tidy:preparatory
- [ ] tests:unit (BinanceMarginAPITests — target 10 tests)

## Changes Made

### 2026-08-08: Add fetchIsolatedMarginAccount closure + BinanceIsolatedMarginAccount DTO to BinanceAPIClient

**feat**

- `EasyCrypto/Core/Models/MarginBalance.swift`: Modified
- `EasyCrypto/Core/Services/BinanceAPIClient.swift`: Modified
- `EasyCryptoTests/Core/Models/MarginBalanceTests.swift`: Modified
- `EasyCryptoTests/Core/Models/TradingModeTests.swift`: Modified
- `EasyCryptoTests/Core/Services/BinanceMarginAPITests.swift`: Modified
- `EasyCryptoTests/Core/Services/PriceServiceTests.swift`: Modified
- `EasyCryptoTests/Core/Services/TradeImportServiceTests.swift`: Modified
- `arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-005.md`: Modified
- `arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-006.md`: Modified
- `arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-007.md`: Modified
- `arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-008.md`: Modified
- `docs/1.project-overview.md`: Modified
- `EasyCrypto/Core/Services/MarginTradeImportService.swift`: Added
- `EasyCryptoTests/Core/Services/MarginTradeImportServiceTests.swift`: Added

