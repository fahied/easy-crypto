---
advance:
  id: "ADV-PORTFOLIO-001"
  title: "Holdings match Binance: use account balances as authoritative quantity"
  system: "easycrypto-core"
  primary_component: "portfolio"
  components: ["portfolio", "holdings", "core-services", "core-models", "app-shell"]
  started_at: "2026-06-28T00:00:00Z"
  implementation_completed_at: "2026-06-28T00:00:00Z"
  review_time_estimate_minutes: 45
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: ["tdd:red-green", "tests:unit"]
  # Populated by `arrive usage import` / the LiteLLM callback — leave empty when authoring.
  model_usage: []
  status: complete
---

## Objective

Make the app's holding quantities match the Binance app exactly by using the live
**account balances** (`GET /api/v3/account`, `free + locked`) as the authoritative
per-asset quantity, instead of reconstructing quantity from spot trade history.
Cost basis, average buy price, and realized P&L continue to come from FIFO over the
trade history.

## Problem (observed)

Side-by-side with the Binance app, quantities drift and USDT is missing:

| Asset | EasyCrypto (now) | Binance (actual) | Delta |
|-------|------------------|------------------|-------|
| BTC   | 0.61362343       | 0.59803146       | +0.0156 |
| XRP   | 19,594.6696      | 19,594.5858      | +0.0838 |
| ETH   | 8.7927           | 8.79302181       | −0.0003 |
| USDT  | (not shown)      | 67,395.12800157  | missing |

### Root cause

Both [PortfolioProcessor](../../../../EasyCrypto/Features/Portfolio/PortfolioProcessor.swift)
and [HoldingsProcessor](../../../../EasyCrypto/Features/Holdings/HoldingsProcessor.swift)
set `totalQuantity = fifoResult.totalRemainingQuantity` — a value rebuilt from the
synced `myTrades` history. That reconstruction omits everything that is not a spot
trade: fees paid in BNB, internal transfers (Spot ↔ Funding/Earn), conversions,
dust, airdrops, and Earn/staking rewards. The `/account` endpoint is currently used
only to *discover asset names*, not as the source of truth for quantity, so the
displayed amounts diverge from the wallet and the quote asset (USDT) never appears.

## Behavioral Change

After this advance:
- Each holding's quantity equals the Binance account balance (`free + locked`) for
  that asset — matching the Binance app to the displayed precision.
- USDT appears as a holding valued 1:1 (no P&L), so the portfolio total reflects the
  full wallet like Binance.
- Average buy price, invested, realized P&L still derive from FIFO; unrealized P&L is
  recomputed against the authoritative quantity:
  `unrealizedPnL = (currentPrice − weightedAvgBuyPrice) × balanceQuantity`.
- Assets held on Binance but with no local trade history still show (quantity +
  value), with cost basis shown as unavailable rather than fabricated.

## Design Decisions

1. **Quantity source = live balances** (`free + locked`). FIFO remaining-quantity is
   no longer used for display, only for cost basis / realized P&L.
2. **USDT shown** as a 1:1 holding with zero P&L (matches Binance's wallet view).
3. **Cost basis for balance not explained by trades** (e.g. rewards/airdrops): apply
   the FIFO `weightedAvgBuyPrice` across the whole balance for unrealized P&L; when
   there are no buy lots, mark cost basis/avg price as unavailable and show P&L as 0.
4. **Dust**: keep showing small balances for now (matches Binance "show all"); a
   hide-dust threshold is deferred.

## Design Notes

- **core-services**: add a small `BalanceService` (struct-with-closures) wrapping
  `BinanceAPIClient.fetchAccount`, returning `[asset: quantity]` (`free + locked`,
  non-zero). Keeps the apiClient out of the processors and is preview/noop-friendly.
- **core-models**: add an `AccountBalance` `@Model` (`asset`, `quantity`,
  `updatedAt`) persisted during portfolio refresh, so the Holdings tab (which does
  not run a sync) can read authoritative quantities offline. Register in the schema.
- **portfolio**: in `refresh()`, fetch balances via `BalanceService`, upsert
  `AccountBalance` rows, then build holdings keyed by balance asset — quantity from
  `AccountBalance`, cost basis from FIFO, P&L recomputed against balance quantity;
  include USDT.
- **holdings**: `loadHoldings()` reads persisted `AccountBalance` for quantity
  (fallback to FIFO only if a balance row is missing) and recomputes P&L the same way.
- **app-shell**: construct `BalanceService.live(apiClient:)`, inject into the
  Portfolio/Holdings processors, and register `AccountBalance.self` in the
  `ModelContainer` schema.

## Planned Implementation Tasks

- [x] test (core-services): `BalanceService.live` maps `fetchAccount` to non-zero
      `free + locked` per asset
- [x] test (core-models): `AccountBalance` round-trips
- [x] test (portfolio): holdings use balance quantity (not FIFO), USDT is included,
      and unrealized P&L = (price − avgBuy) × balanceQty
- [x] test (holdings): quantity comes from persisted `AccountBalance`; falls back to
      FIFO when no balance row exists
- [x] feat (core-services): add `BalanceService`
- [x] feat (core-models): add `AccountBalance`; register in schema
- [x] feat (portfolio): balance-driven holdings + USDT + P&L recompute + persist
- [x] feat (holdings): balance-driven quantity + P&L recompute
- [x] feat (app-shell): wire `BalanceService` and register the model

## Bug Fixes

- [x] Holding quantities reconstructed from trade history instead of the wallet
      balance (this advance's core fix).

## Risk + Rollback

- Risk: `/account` requires API permissions; on fetch failure, fall back to the last
  persisted `AccountBalance` (and then FIFO) so the UI degrades gracefully rather
  than emptying.
- Risk: mixing live quantity with FIFO cost basis can make P&L approximate when the
  balance exceeds traded quantity (rewards/airdrops) — handled by Design Decision 3.
- Risk: additive model — new `AccountBalance` entity is non-breaking (lightweight
  SwiftData migration); existing data untouched.
- Rollback: revert the advance's commits; processors fall back to the prior
  FIFO-quantity behavior and the new entity/service become inert.

## Evidence

- [x] tdd:red-green
- [x] tests:unit (BalanceService, AccountBalance model, Portfolio + Holdings
      balance-driven quantity/P&L — 4 new tests + updated existing suites; full
      EasyCryptoTests suite green — `** TEST SUCCEEDED **`)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-PORTFOLIO-001 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-28 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-PORTFOLIO-001.md: created advance plan

### 2026-06-28 - fix: holdings match Binance wallet balances
- EasyCrypto/Core/Models/AccountBalance.swift: new `@Model` (asset, quantity, updatedAt) snapshot of wallet balances
- EasyCrypto/Core/Services/BalanceService.swift: new service mapping `fetchAccount` → non-zero `free + locked` per asset
- EasyCrypto/Core/Services/HoldingFactory.swift: builds a `Holding` from wallet quantity + FIFO cost basis; P&L = (price − avgBuy) × qty; no-cost-basis → P&L 0
- EasyCrypto/Features/Portfolio/PortfolioProcessor.swift: inject `BalanceService`; balance-driven holdings + USDT; persist `AccountBalance`; realized P&L still summed across all traded assets; graceful fallback to persisted balances on fetch failure
- EasyCrypto/Features/Holdings/HoldingsProcessor.swift: read persisted `AccountBalance` for quantity (fallback to FIFO remaining when none); P&L recompute via `HoldingFactory`
- EasyCrypto/EasyCryptoApp.swift: register `AccountBalance.self` in the schema
- EasyCrypto/ContentView.swift: inject `BalanceService.live(apiClient:)` into the portfolio processor
- EasyCrypto/Core/Models/PreviewSampleData.swift, EasyCrypto/Features/Holdings/HoldingsListView.swift: add `AccountBalance.self` to in-memory preview containers
- EasyCryptoTests: BalanceServiceTests (1), AccountBalanceTests (1), Portfolio `usesBalanceQuantityAndIncludesUSDT` (1), Holdings `usesPersistedBalanceQuantity` (1); updated Portfolio/Holdings suites to supply balances and register the model

## Check for Understanding

1. Why do the current holding quantities drift from the Binance app, and which line
   in `PortfolioProcessor`/`HoldingsProcessor` is the root cause?
2. After this advance, what is the source of truth for quantity versus for cost
   basis and realized P&L?
3. Why does the Holdings tab need a persisted `AccountBalance` model rather than just
   calling `/account` like the Portfolio refresh does?
4. How is unrealized P&L recomputed once quantity comes from the live balance, and
   how is the case of a balance larger than the traded quantity handled?
5. Why is USDT now shown as a holding, and what P&L does it carry?
