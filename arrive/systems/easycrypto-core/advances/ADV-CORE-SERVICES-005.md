---
advance:
  id: "ADV-CORE-SERVICES-005"
  title: "Add Binance margin REST API endpoints to BinanceAPIClient"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services"]
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

Extend `BinanceAPIClient` with the Binance margin REST API endpoints required to
fetch cross-margin and isolated-margin data: account overview, margin trades,
margin open orders, all margin assets, and isolated-mymbol transfer history.
Depends on ADV-CORE-MODELS-002 (TradingMode enum).

## Behavioral Change

After this advance:

- `BinanceAPIClient` exposes new closure properties:
  - `fetchMarginAccount` — `GET /sapi/v1/margin/account` (cross-margin account overview:
    margin level, total asset/liability, net asset, max borrow per asset)
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
- Response DTOs added: `BinanceMarginAccount`, `BinanceMarginAsset`, `BinanceMarginTrade`,
  `BinanceMarginOrder`, `BinanceMarginTransfer`.
- The `live()` implementation populates the new closures. `preview` and `noop` variants
  return empty data for margin closures.

## Design Notes

- **Endpoint base path**: Margin endpoints use `/sapi/v1/` (signed REST), not `/api/v3/`.
  The URL builder already supports signed URLs; only the path prefix changes.
- **Isolated vs cross flag**: The `isIsolated` query parameter distinguishes isolated
  from cross-margin on shared endpoints (`myTrades`, `openOrders`). The closures accept
  a boolean `isIsolated` parameter to set this flag.
- **No behavior change to existing closures**: `fetchAccount`, `fetchMyTrades`, etc.
  continue to call spot endpoints exclusively. The new closures are additive.
- **Error extension**: Add `.invalidMode("...")` to `BinanceError` for callers that
  accidentally request margin data with `.spot` mode.

## Component Impact

- **core-services** (`EasyCrypto/Core/Services/BinanceAPIClient.swift`):
  - Add `BinanceMarginAccount`, `BinanceMarginAsset`, `BinanceMarginTrade`,
    `BinanceMarginOrder`, `BinanceMarginTransfer` response DTOs
  - Add closure properties to `BinanceAPIClient` struct
  - Populate in `live()` extension
  - Provide `preview` / `noop` implementations

## Out of Scope

- Margin trade import orchestration (ADV-CORE-SERVICES-006)
- Margin balance aggregation (ADV-CORE-SERVICES-007)
- Margin order placement (not planned — read-only)
- WebSocket margin streams (not planned)
- Isolated-margin interest rate fetching (not planned)
- Margin loan/repay endpoints (not planned)

## Planned Implementation Tasks

- [ ] test: `fetchMarginAccount` DTO decodes correctly from sample JSON
- [ ] test: `fetchMarginMyTrades` with `isIsolated=true/false` returns correct data
- [ ] test: `fetchMarginAllAssets` decodes asset list with borrowed/free/locked
- [ ] test: calling margin closure with `.spot` throws `.invalidMode`
- [ ] test: preview/noop variants return empty data for all margin closures
- [ ] tidy: add `BinanceMarginAccount`, `BinanceMarginAsset`, `BinanceMarginTrade`,
      `BinanceMarginOrder`, `BinanceMarginTransfer` DTOs
- [ ] tidy: add `fetchMarginAccount`, `fetchMarginMyTrades`, `fetchMarginOpenOrders`,
      `fetchMarginAllAssets`, `fetchIsolatedMarginTransfers` to `BinanceAPIClient`
- [ ] tidy: populate new closures in `live()` with correct `/sapi/v1/margin/*` paths

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: additive new closures + DTOs only. No existing code path changes.
- Rollback: revert commits. No migration or data change needed.

## Evidence

- [ ] tidy:preparatory
- [ ] tests:unit (BinanceMarginAPITests — target 8 tests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-SERVICES-005 --status passed`

## Changes Made

*(populated during implementation)*

## Check for Understanding

1. Why do margin endpoints use `/sapi/v1/` while spot endpoints use `/api/v3/`,
    and how does the existing `BinanceURLBuilder` accommodate both?
2. What does the `isIsolated` query parameter do on shared margin endpoints, and how
    does the closure API expose it?
3. Why does this advance add new closures rather than extending existing ones like
    `fetchMyTrades`?
