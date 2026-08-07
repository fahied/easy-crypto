---
advance:
  id: "ADV-CORE-MODELS-002"
  title: "Tidy-up: introduce TradingMode abstraction to decouple spot assumptions from core models"
  system: "easycrypto-core"
  primary_component: "core-models"
  components: ["core-models", "core-services"]
  started_at: "2026-08-07T09:00:00Z"
  implementation_completed_at: ~
  review_time_estimate_minutes: 20
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  model_usage: []
  status: planned
---

## Objective

Refactor the existing spot-only models (`Trade`, `AccountBalance`, `SyncMetadata`) to carry an
explicit `tradingMode` field, and introduce a `TradingMode` enum and `MarginBalance`
model so that cross-margin and isolated-margin data can coexist with spot data in the
same SwiftData store without structural conflict. No behavior changes; all fields default
to `spot` so existing data and all downstream logic remain backward-compatible.

This is a preparatory (tidy) advance — it introduces zero new user-facing functionality
and changes no computed output. Its purpose is to eliminate the hidden assumption that
every trade and balance is a spot trade, so that subsequent advances (ADV-CORE-SERVICES-005
through ADV-PORTFOLIO-002) can add margin support incrementally.

## Behavioral Change

After this advance:

- `Trade` has a `tradingMode: TradingMode` field (default `spot`). Existing persisted
  trades deserialize as `.spot` because the stored default matches.
- `AccountBalance` has a `tradingMode: TradingMode` field (default `spot`).
- `SyncMetadata` has a `tradingMode: TradingMode` field. The unique key becomes
  `[\.symbol, \.tradingMode]` so cross-margin and isolated-margin sync cursors for the
  same symbol don't collide.
- New `TradingMode` enum: `.spot`, `.crossMargin`, `.isolatedMargin`.
- New `MarginBalance` SwiftData model persists isolated-margin asset balances
  (borrowed, free, locked, interest) with a unique key on `[\.symbol, \.isolatedMarginKey]`.
  Cross-margin debts are a view-level derivation (no persistent model needed — they're
  returned as a list from `/sapi/v1/margin/account`).
- `BinanceAPIClient` closure signatures accept a `TradingMode` parameter where needed,
  and the `live()` implementation dispatches to the correct endpoint path based on mode.
- `TradeImportService.sync` accepts an optional `TradingMode` parameter; default `nil`
  means "spot" for backward compatibility.
- `BalanceService.fetchBalances` accepts an optional `TradingMode`; default still returns
  spot balances.

No computed output (holdings, P&L, alerts, insights) changes — they continue to
operate on spot data only until the follow-up advances wire margin data in.

## Design Notes

- **Enum, not string**: `TradingMode` is a `String`-backed enum so it's Codable with
  stable raw values and works in `#Predicate` filters.
- **Default = spot**: Every new field defaults to `.spot`. SwiftData migrations for
  existing records apply the default automatically (no manual migration block required
  because the field is non-optional).
- **SyncMetadata dual key**: The unique index changes from `symbol` to `(symbol, tradingMode)`.
  This means a single symbol (e.g., `BTCUSDT`) can have three independent sync cursors:
  one for spot, one for cross-margin, one for isolated-margin.
- **MarginBalance lives separately**: It doesn't replace `AccountBalance`; it complements
  it. Spot balances stay in `AccountBalance`. Isolated-margin balances (which have
  borrowing semantics) go in `MarginBalance`. Cross-margin has no per-asset balance
  table — it's a single aggregated account view.
- **BinanceAPIClient closure extension**: Adding a `tradingMode` parameter to existing
  closures would break all callers. Instead, the tidy introduces a *parallel* set of
  closures: `fetchMarginAccount`, `fetchMarginMyTrades`, etc. The original closures
  remain untouched. The live implementation conditionally dispatches based on a mode
  parameter when closures are invoked.

## Component Impact

- **core-models** (`EasyCrypto/Core/Models/**`):
  - New `TradingMode.swift` — enum definition
  - `Trade.swift` — add `tradingMode` field (default `.spot`)
  - `AccountBalance.swift` — add `tradingMode` field (default `.spot`)
  - `SyncMetadata.swift` — add `tradingMode` field; unique key becomes `(symbol, tradingMode)`
  - New `MarginBalance.swift` — `@Model` for isolated-margin asset balances

- **core-services** (`EasyCrypto/Core/Services/**`):
  - `BinanceAPIClient.swift` — add margin closure properties (`fetchMarginAccount`,
    `fetchMarginMyTrades`, `fetchMarginOpenOrders`, `fetchMarginAllAssets`);
    `live()` populates them with correct endpoint paths
  - `TradeImportService.swift` — add optional `TradingMode` parameter to `sync`
    closure; default `nil` → spot
  - `BalanceService.swift` — add optional `TradingMode` parameter to `fetchBalances`
    closure; default `nil` → spot

## Out of Scope

- No new user-facing UI for margin mode selection (ADV-SETTINGS-003)
- No margin trade import yet (ADV-CORE-SERVICES-006)
- No margin P&L calculation (ADV-CORE-SERVICES-007)
- No margin balance display in Holdings (ADV-CORE-SERVICES-008, ADV-PORTFOLIO-002)
- No margin trade history (ADV-TRADE-HISTORY-001)
- No background margin refresh (ADV-APP-SHELL-002)
- No migration block — defaults handle it

## Planned Implementation Tasks

- [ ] test: TradingMode enum codable round-trip; predicate filtering by mode
- [ ] test: Trade with default tradingMode deserializes as .spot
- [ ] test: SyncMetadata unique key enforces (symbol, tradingMode) composite
- [ ] test: MarginBalance model persistence + fetch by isolatedMarginKey
- [ ] tidy: add `TradingMode` enum (`.spot`, `.crossMargin`, `.isolatedMargin`)
- [ ] tidy: add `tradingMode` field to `Trade` (default `.spot`)
- [ ] tidy: add `tradingMode` field to `AccountBalance` (default `.spot`)
- [ ] tidy: update `SyncMetadata` unique key to `(symbol, tradingMode)`
- [ ] tidy: add `MarginBalance` model (isolated margin asset balances)
- [ ] tidy: register `MarginBalance` in `EasyCryptoApp` ModelContainer schema
- [ ] tidy: add margin closures to `BinanceAPIClient` (`fetchMarginAccount`,
      `fetchMarginMyTrades`, `fetchMarginOpenOrders`, `fetchMarginAllAssets`)
- [ ] tidy: add optional `TradingMode` parameter to `TradeImportService.sync`
- [ ] tidy: add optional `TradingMode` parameter to `BalanceService.fetchBalances`

## Bug Fixes

- [ ] None — tidy-only advance

## Risk + Rollback

- Risk: SwiftData schema change — two existing models (`Trade`, `AccountBalance`) gain a
  non-optional field with a default. SwiftData handles this as a migration automatically
  (default applied to existing rows). The `SyncMetadata` unique key change from single
  to composite may require an index rebuild — verify on first launch with existing data.
- Risk: `SyncMetadata` unique key migration — if the store already has rows, changing
  the unique constraint could fail on the first insert. Mitigation: implement a manual
  migration block that drops and recreates the unique index, or use a versioned migration.
- Rollback: revert the commits. SwiftData will recreate the store schema on next launch
  (data loss of trade/balance/sync data unless a backup strategy exists). Since this
  is a tidy advance on a development branch, the risk is acceptable.

## Evidence

- [ ] tidy:preparatory
- [ ] tests:unit (TradingModeTests, MarginBalanceTests, SyncMetadataCompositeKeyTests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-MODELS-002 --status passed`

## Changes Made

*(populated during implementation)*

## Check for Understanding

1. Why does `TradingMode` use a `String`-backed enum instead of a plain enum or string property?
2. How does the composite unique key `(symbol, tradingMode)` on `SyncMetadata` allow
   the same symbol to have independent sync cursors for spot, cross-margin, and
   isolated-margin trades?
3. Why does this advance add `MarginBalance` as a separate model instead of extending
   `AccountBalance` with optional margin fields?
4. How does adding optional `TradingMode` parameters to `TradeImportService` and
   `BalanceService` preserve backward compatibility with existing callers?
