# EasyCrypto

> A read-only Binance spot portfolio tracker for iOS 26+, built with SwiftUI, SwiftData, and Swift 6.

---

## Intent

The Binance iOS app doesn't give you a clear picture of how much you've invested per coin, your weighted average buy price, or how DCA affects your position over time.

**EasyCrypto** solves this by importing your Binance spot trade history via the official API and presenting a clean, USDT-denominated view of your entire portfolio — including unrealized P&L, FIFO-based realized P&L, and per-coin breakdowns.

No trading. No WebSocket. Your data stays on device.  
Pull to refresh for an accurate snapshot — plus optional background price/candle alerts and **on-device AI insights** powered by Apple Foundation Models.

---

## Features

| Tab | Description |
|---|---|
| **Portfolio** | Summary metric cards (total invested, current value, unrealized P&L, realized P&L) + scrollable holdings list with sort picker |
| **Holdings** | Per-coin list showing avg cost, current price, qty, and P&L. Tap a coin → Coin Detail |
| **Coin Detail** | Glass summary card + Swift Charts line chart (1h / 4h / 1d / 1w) + full trade list |
| **Trade History** | Chronological trade list grouped by date, filterable by coin. BUY (green) / SELL (red) |
| **Insights** | On-device AI analysis of your trade history — patterns, risks, and suggestions — via Apple Foundation Models. Refreshed every ~4 hours; never leaves your device |
| **Settings** | Binance API key + secret, test connection, sync stats, per-coin price & candle-drop alerts, AI-insights toggle, clear all data |

---

## Requirements

| | |
|---|---|
| iOS | **26.0+** |
| Xcode | **26+** |
| Swift | **6.2** |
| Binance account | Read-only API key + secret |
| Apple Intelligence | Required for **AI Insights** only — every other feature works without it |

---

## Getting Started

1. Clone the repo and open `EasyCrypto.xcodeproj` in Xcode 26+
2. Build & run on an iOS 26 simulator or device (`⌘R`)
3. Open the **Settings** tab → enter your Binance API key and secret → tap **Test Connection**
4. Pull to refresh on the **Portfolio** tab to import trades and fetch current prices

> **Binance API permissions needed:** "Enable Reading" only.  
> No trading, spot, or withdrawal permissions required.

---

## Architecture — MVI

Unidirectional data flow. State is never mutated directly by views.

```
User/System Action
  → Intent (enum)
    → Processor (@Observable class — handles intents, performs async side effects)
      → State (single source of truth)
        → View (pure SwiftUI — renders state, sends intents back)
```

Each feature owns four files:

```
Feature/
├── FeatureIntent.swift      — enum of all possible user/system actions
├── FeatureState.swift       — @Observable class holding all view data
├── FeatureProcessor.swift   — receives intents, runs side effects, updates state
└── FeatureView.swift        — SwiftUI view driven by state
```

---

## Project Structure

```
EasyCrypto/
├── EasyCryptoApp.swift              — App entry point, ModelContainer + background tasks
├── ContentView.swift                — TabView shell (Portfolio · Holdings · History · Insights · Settings)
├── Core/
│   ├── Architecture/
│   │   └── MVI.swift                — Base Processor protocol + intent dispatch
│   ├── Models/                      — SwiftData @Model + value types
│   │   ├── Trade.swift              — persisted Binance trade record
│   │   ├── SyncMetadata.swift       — last synced trade ID per symbol
│   │   ├── AccountBalance.swift     — persisted balance snapshot (offline holdings)
│   │   ├── PriceAlertConfig.swift   — per-coin alert settings + de-dup state
│   │   ├── CandleAlertState.swift   — hourly candle-drop throttle
│   │   ├── NotificationLogEntry.swift — delivered-notification history
│   │   ├── TradingInsight.swift     — persisted AI insight
│   │   ├── InsightState.swift       — 4-hour insight-regeneration throttle
│   │   ├── Holding.swift / PortfolioSummary.swift / Kline.swift / DailyPnL.swift
│   ├── Services/                    — struct-with-closures clients
│   │   ├── BinanceAPIClient.swift   — URLSession + HMAC-SHA256 signing
│   │   ├── KeychainService.swift    — secure credential storage
│   │   ├── TradeImportService.swift — discover → paginate → persist sync flow
│   │   ├── PriceService.swift / BalanceService.swift
│   │   ├── FIFOCalculator.swift     — FIFO cost-basis & realized-P&L engine
│   │   ├── HoldingFactory.swift / UnrealizedProfit.swift
│   │   ├── PriceAlertService.swift  — profit / price-move alert evaluation
│   │   ├── CandleAlertService.swift — consecutive candle-drop detection
│   │   └── NotificationService.swift — local notification delivery
│   └── AI/                          — on-device AI insights (Foundation Models)
│       ├── TradeSummary.swift           — bounded, Sendable summary (privacy boundary)
│       ├── TradePatternSummarizer.swift — pure ledger → TradeSummary reducer
│       ├── InsightGeneration.swift      — @Generable schema, prompt, draft mapper
│       ├── FoundationModelInsightEngine.swift — availability-gated on-device engine
│       └── InsightSettingsStore.swift   — enable/disable toggle (UserDefaults)
├── BackgroundTasks/
│   ├── PriceAlertRefresher.swift    — background price/profit alert check
│   ├── CandleAlertRefresher.swift   — hourly candle-drop check
│   └── InsightRefresher.swift       — ~4-hour on-device insight regeneration
├── Features/
│   ├── Portfolio/                   — Dashboard tab
│   ├── Holdings/                    — Holdings list + Coin Detail screen
│   ├── TradeHistory/                — Trade history tab
│   ├── Insights/                    — AI insights tab (MVI)
│   └── Settings/                    — API key, alerts, AI toggle
└── DesignSystem/
    ├── GlassCard.swift              — iOS 26 glass container ViewModifier
    ├── PnLLabel.swift               — Colored P&L text with ▲▼ arrow
    ├── MetricCard.swift             — Single KPI card (label + value)
    ├── TradeRowView.swift           — Reusable trade list row
    └── Theme.swift                  — Color and typography tokens
```

---

## Key Business Logic

### FIFO Cost Basis
Each buy creates a lot `(price, quantity)`. On sell, lots are consumed earliest-first:

- **Realized P&L** = sell proceeds − cost basis of consumed lots − commissions
- **Unrealized P&L** = (current price − weighted avg cost) × remaining qty
- **Weighted avg cost** = Σ(lot.qty × lot.price) / Σ(lot.qty) across remaining lots

### Sync Strategy
1. `GET /api/v3/account` (`omitZeroBalances=true`) → discover held asset names
2. For each asset, construct USDT pair (e.g. `BTC` → `BTCUSDT`)
3. `GET /api/v3/myTrades` per symbol; use `fromId` from `SyncMetadata` for incremental sync
4. Paginate: repeat with `fromId = lastTradeId + 1` while page returns 1000 results
5. `GET /api/v3/ticker/price` for all held symbols → current prices
6. Persist new trades in SwiftData, update `SyncMetadata.lastTradeId`

---

## On-Device AI Insights

The **Insights** tab analyzes your trade history entirely on device using Apple's
**Foundation Models** framework (`SystemLanguageModel`). No trade data ever leaves
your iPhone — there is no network call in the insight path and no cloud model.

**How it works**
1. `TradePatternSummarizer` reduces your full ledger into a small, bounded
   `TradeSummary` (per-symbol counts, FIFO realized P&L, win rate, streaks,
   concentration). This summary — never raw trades — is the only thing the model sees.
2. `FoundationModelInsightEngine` runs **guided generation** (`@Generable`) to
   produce typed insights (title, body, category, severity), validated before they
   are persisted.
3. Insights regenerate on a best-effort **4-hour** cadence in the background, plus a
   manual “Analyze” button. They persist in SwiftData so the screen renders instantly.

**Privacy & graceful degradation**
- 100% on device; the engine performs zero network I/O and has no remote fallback.
- Requires Apple Intelligence; on unsupported devices the tab shows a neutral
  “unavailable” message instead of failing.
- Toggle the feature on or off anytime in **Settings**.

---

## Dependency Injection

Services use the **struct-with-closures** pattern (no protocols) and are injected
through **initializers** — there is no external DI framework. Each service ships
`live`, `preview`, and `noop` values for production, SwiftUI previews, and tests.

```swift
// Definition
nonisolated struct PriceService: Sendable {
    var fetchPrices: @Sendable (_ symbols: [String]) async throws -> [String: Double]
}

// Live, preview, and noop values
extension PriceService {
    static func live(apiClient: BinanceAPIClient = .live()) -> PriceService { ... }
    static let preview = PriceService(fetchPrices: { _ in ["BTCUSDT": 65_000] })
    static let noop    = PriceService(fetchPrices: { _ in [:] })
}

// Injected via initializer; tests pass stub values directly
@Observable
class PortfolioProcessor {
    private let priceService: PriceService
    init(priceService: PriceService /* , … */) {
        self.priceService = priceService
    }
}
```

---

## Security

| Concern | Mitigation |
|---|---|
| API key + secret | Stored in **iOS Keychain only** — never in SwiftData, UserDefaults, or files |
| Logging | Keys, secrets, and HMAC signatures are **never** logged |
| Network | HTTPS only — Binance API enforces TLS |
| API scope | Read-only permissions — the app cannot place or cancel orders |

---

## Testing

Written with **Swift Testing** (`@Suite`, `@Test`, `#expect`, `#require`). TDD throughout — tests written before implementation at every step.

```
EasyCryptoTests/
├── Core/
│   ├── Architecture/
│   │   └── ProcessorTests.swift
│   ├── Models/
│   │   ├── TradeModelTests.swift
│   │   ├── SyncMetadataTests.swift
│   │   ├── HoldingTests.swift
│   │   ├── PortfolioSummaryTests.swift
│   │   └── KlineTests.swift
│   └── Services/
│       ├── BinanceAPIClientTests.swift    — HMAC signing, URL construction, error mapping
│       ├── KeychainServiceTests.swift
│       ├── FIFOCalculatorTests.swift      — FIFO scenarios, DCA, partial sells, commissions
│       ├── TradeImportServiceTests.swift  — Pagination, incremental sync, mapping
│       └── PriceServiceTests.swift        — Batch fetch, empty input, error propagation
└── Features/
    ├── Portfolio/PortfolioProcessorTests.swift
    ├── Holdings/HoldingsProcessorTests.swift
    ├── Holdings/CoinDetailProcessorTests.swift
    ├── TradeHistory/TradeHistoryProcessorTests.swift
    ├── Settings/SettingsProcessorTests.swift
    └── Insights/InsightsProcessorTests.swift
```

The AI-insights layer is covered by `Core/AI` tests (`TradePatternSummarizerTests`,
`FoundationModelInsightEngineTests`), model round-trips (`TradingInsightTests`),
`InsightRefresherTests`, and `SettingsInsightsTests` — all using injected stubs so no
real LLM call runs in tests.

Coverage targets: **≥ 80%** all layers · **≥ 90%** `FIFOCalculator`

Run tests:
```bash
xcodebuild test \
  -project EasyCrypto.xcodeproj \
  -scheme EasyCrypto \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

---

## Progress

### ✅ Phase 1 — Core Layer (Complete)

| Step | What was built |
|---|---|
| **1.1 Models** | `Trade` + `SyncMetadata` SwiftData `@Model` classes; `Holding`, `PortfolioSummary`, `Kline` value types; full test suite |
| **1.2 Keychain** | `KeychainService` — save/load/delete Binance credentials via iOS Security framework |
| **1.3 API Client** | `BinanceAPIClient` — HMAC-SHA256 signing, `fetchAccount`, `fetchMyTrades`, `fetchTickerPrices`, `fetchKlines`; error mapping to `BinanceError` |
| **1.4 FIFO Calculator** | `FIFOCalculator` — lot tracking, partial sells, DCA, commission handling; ≥ 90% coverage |
| **1.5 Trade Import** | `TradeImportService` — full sync orchestration with asset discovery, pagination, incremental sync via `SyncMetadata` |
| **1.6 Price Service** | `PriceService` — batch ticker fetch, `[String: Double]` mapping, empty-input short-circuit |

### ✅ Phase 2 — MVI Feature Layer (Complete)

| Step | What was built |
|---|---|
| **2.1 MVI Base** | `Processor` base class with `send(_ intent:)` dispatch; `@Observable` state pattern |
| **2.2 Portfolio** | `PortfolioProcessor` — refresh, sort, P&L aggregation; `PortfolioView` with glass metric cards + holdings list |
| **2.3 Holdings** | `HoldingsProcessor` + `CoinDetailProcessor`; `HoldingsListView` + `CoinDetailView` with Swift Charts line chart |
| **2.4 Trade History** | `TradeHistoryProcessor`; chronological list grouped by date with coin filter chips |
| **2.5 Settings** | `SettingsProcessor`; API key entry, test connection, sync stats, clear data |

### ✅ Phase 3 — App Shell (Complete)

| What was built |
|---|
| `TabView` shell with iOS 26 glass tab bar |
| Onboarding flow — no credentials → guided Settings prompt |
| Empty state — credentials saved but no trades → pull-to-refresh prompt |
| Binance `-1021` timestamp fix — server time sync on auth failure |
| Processor state preservation fix — `@State` ownership in views |

### ✅ Phase 4 — Alerts & On-Device AI (Complete)

| What was built |
|---|
| Per-coin **price/profit alerts** + **consecutive candle-drop** detection with local notifications and a notification log |
| **Background tasks** (`BGAppRefreshTask`) running the price, candle, and insight refreshers |
| **On-device AI Insights** — `TradeSummary` reducer, `@Generable` Foundation Models engine, Insights MVI tab, Settings toggle, and a ~4-hour background refresher |

---

## Dependencies

**No third-party packages.** Everything is built on Apple frameworks:

SwiftUI · SwiftData · Swift Charts · **FoundationModels** (on-device AI) · CryptoKit · Security · BackgroundTasks · UserNotifications · URLSession · `os.Logger`

---

## Future Enhancements

### Near-term
- [ ] **Real-time prices** — WebSocket connection to Binance stream for live price updates without manual refresh
- [x] **Price alerts** — per-coin profit & price-move notifications, plus consecutive candle-drop alerts
- [x] **On-device AI insights** — trade-pattern analysis & suggestions via Apple Foundation Models
- [ ] **Widget** — iOS home screen widget showing portfolio value and daily P&L
- [ ] **CSV / PDF export** — export trade history for tax reporting
- [ ] **Candlestick chart** — replace line chart with OHLCV candlestick in Coin Detail

### Data & Accuracy
- [ ] **BNB commission rebate** — accurately account for trades where commission is paid in BNB rather than the base asset
- [ ] **Non-USDT pairs** — support BTC-denominated pairs (e.g. `ETHBTC`) with automatic conversion to USDT equivalent
- [ ] **Multi-account support** — switch between multiple Binance accounts
- [ ] **Staking / earn** — surface locked/staked balances separately from spot holdings

### UX & Design
- [ ] **Haptic feedback** — subtle haptics on pull-to-refresh complete and connection test result
- [ ] **Coin icons** — fetch and cache CoinGecko or Binance coin logos
- [ ] **Dark / light theme picker** — manual override in addition to system setting
- [ ] **Accessibility** — VoiceOver labels and Dynamic Type support throughout

### Engineering
- [ ] **SwiftData schema versioning** — `VersionedSchema` + `SchemaMigrationPlan` for the first model migration
- [x] **Background App Refresh** — periodic price/candle-alert checks and ~4-hour on-device insight regeneration
- [ ] **Retry logic** — exponential back-off for rate-limit (HTTP 429) responses
- [ ] **Snapshot tests** — visual regression tests for design system components

---

## Documentation

- [`docs/1.project-overview.md`](docs/1.project-overview.md) — full feature spec, data models, Binance API details, acceptance criteria
- [`docs/2.technical-direction.md`](docs/2.technical-direction.md) — architecture decisions, concurrency model, DI patterns, logging rules, preview strategy, testing methodology
