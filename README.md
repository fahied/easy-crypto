# EasyCrypto

> A read-only Binance spot portfolio tracker for iOS 26+, built with SwiftUI, SwiftData, and Swift 6.

---

## Intent

The Binance iOS app doesn't give you a clear picture of how much you've invested per coin, your weighted average buy price, or how DCA affects your position over time.

**EasyCrypto** solves this by importing your Binance spot trade history via the official API and presenting a clean, USDT-denominated view of your entire portfolio — including unrealized P&L, FIFO-based realized P&L, and per-coin breakdowns.

No trading. No WebSocket. No background refresh.  
Just a clean, accurate snapshot whenever you pull to refresh.

---

## Features

| Tab | Description |
|---|---|
| **Portfolio** | Summary metric cards (total invested, current value, unrealized P&L, realized P&L) + scrollable holdings list with sort picker |
| **Holdings** | Per-coin list showing avg cost, current price, qty, and P&L. Tap a coin → Coin Detail |
| **Coin Detail** | Glass summary card + Swift Charts line chart (1h / 4h / 1d / 1w) + full trade list |
| **Trade History** | Chronological trade list grouped by date, filterable by coin. BUY (green) / SELL (red) |
| **Settings** | Binance API key + secret management, test connection, sync stats, clear all data |

---

## Requirements

| | |
|---|---|
| iOS | **26.0+** |
| Xcode | **26+** |
| Swift | **6.2** |
| Binance account | Read-only API key + secret |

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
├── EasyCryptoApp.swift              — App entry point, ModelContainer setup
├── ContentView.swift                — TabView shell
├── Core/
│   ├── Architecture/
│   │   └── MVI.swift                — Base Processor class + intent dispatch
│   ├── Models/
│   │   ├── Trade.swift              — @Model: persisted Binance trade record
│   │   ├── SyncMetadata.swift       — @Model: last synced trade ID per symbol
│   │   ├── Holding.swift            — Computed per-coin position (not persisted)
│   │   ├── PortfolioSummary.swift   — Computed portfolio aggregate (not persisted)
│   │   └── Kline.swift              — Chart candlestick data (not persisted)
│   └── Services/
│       ├── BinanceAPIClient.swift   — URLSession + HMAC-SHA256 signing
│       ├── KeychainService.swift    — Secure credential storage (iOS Keychain)
│       ├── TradeImportService.swift — Full sync flow: discover → paginate → persist
│       ├── PriceService.swift       — Batch current-price fetching
│       └── FIFOCalculator.swift     — FIFO cost-basis and realized P&L engine
├── Features/
│   ├── Portfolio/                   — Dashboard tab
│   ├── Holdings/                    — Holdings list + Coin Detail screen
│   ├── TradeHistory/                — Trade history tab
│   └── Settings/                   — API key management tab
└── DesignSystem/
    ├── GlassCard.swift              — iOS 26 .glassEffect() container ViewModifier
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

## Dependency Injection

All services follow the [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) **struct-with-closures** pattern. No protocols needed.

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

// Consumed in processors
@Observable class PortfolioProcessor {
    @ObservationIgnored
    @Dependency(PriceService.self) var priceService
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
    └── Settings/SettingsProcessorTests.swift
```

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

---

## Dependency

| Package | Version | Purpose |
|---|---|---|
| [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | latest | Dependency injection for all services |

All other functionality uses Apple frameworks: SwiftUI · SwiftData · Swift Charts · CryptoKit · Security · URLSession · `os.Logger`

---

## Future Enhancements

### Near-term
- [ ] **Real-time prices** — WebSocket connection to Binance stream for live price updates without manual refresh
- [ ] **Price alerts** — notify when a coin crosses a user-defined price threshold
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
- [ ] **Background App Refresh** — optional lightweight sync when app is backgrounded
- [ ] **Retry logic** — exponential back-off for rate-limit (HTTP 429) responses
- [ ] **Snapshot tests** — visual regression tests for design system components

---

## Documentation

- [`Docs/Project-Brief.md`](Docs/Project-Brief.md) — full feature spec, data models, Binance API details, acceptance criteria
- [`Docs/TECHNICAL-DIRECTION.md`](Docs/TECHNICAL-DIRECTION.md) — architecture decisions, concurrency model, DI patterns, logging rules, preview strategy, testing methodology
