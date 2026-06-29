# EasyCrypto — Project Brief

> Binance Spot Portfolio Tracker for iOS 26+
> Bundle ID: `com.fahied.EasyCrypto`
> Created: May 2026

---

## 1. Problem Statement

The Binance iOS app does not clearly show how much was invested (in USDT) per coin, the overall profit/loss against the buying price, or how DCA (Dollar Cost Averaging) affects the average cost of each position. This makes it difficult to understand portfolio performance at a glance.

## 2. Solution

A read-only iOS portfolio tracker that imports spot trade history from the Binance API and presents a clear, USDT-denominated view of:

- **Per-coin investment**: total USDT invested, weighted average buy price, current value, unrealized P&L
- **Overall portfolio**: total invested vs current value, aggregate P&L
- **Realized P&L**: FIFO-based profit/loss calculation when coins are sold
- **Trade history**: full chronological record of all buy/sell trades

No trading functionality — read-only data with manual pull-to-refresh.

## 3. Target Platform

| Property | Value |
|---|---|
| Platform | iOS 26+ |
| Language | Swift 6.2 |
| UI Framework | SwiftUI (iOS 26 liquid glass design) |
| Persistence | SwiftData |
| Architecture | MVI (Model-View-Intent) |
| Dependencies | [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) (via Xcode SPM) |
| Concurrency | Swift 6 strict concurrency, `@Observable`, `@MainActor` default; networking/computation `nonisolated` |

## 4. Scope & Features

### 4.1 Data Source
- **Binance API** (read-only, API key + secret required)
- Spot trades only — USDT pairs exclusively
- Single Binance account (no multi-account)
- Manual refresh — pull-to-refresh syncs new trades AND fetches latest prices in one action

### 4.2 Tabs

| Tab | Purpose |
|---|---|
| **Portfolio** | Dashboard: summary metric cards (Total Invested, Current Value, Unrealized P&L %, Realized P&L) + scrollable holdings list with sort picker |
| **Holdings** | Per-coin list with avg cost, current price, qty, P&L. Tap → Coin Detail (summary card + line chart + trade list) |
| **History** | Chronological trade list grouped by date, with coin filter chips. BUY (green) / SELL (red) labels |
| **Settings** | Binance API key/secret management, test connection, sync stats, clear all data |

### 4.3 Coin Detail Screen (pushed from Holdings)
- Summary glass card: weighted avg cost, quantity held, total invested, current value, unrealized P&L
- Swift Charts line chart with selectable intervals (1h, 4h, 1d, 1w)
- Scrollable list of all trades for that coin

### 4.4 Onboarding / Empty States
- No API key configured → guide user to Settings tab
- API key saved but no trades synced → prompt pull-to-refresh

## 5. Key Business Logic

### 5.1 P&L Calculation — FIFO Cost Basis
- Each buy creates a "lot" with quantity and price
- On sell: consume lots from the front of the queue (earliest first)
- **Realized P&L** = sell proceeds − cost basis of consumed lots
- **Unrealized P&L** = (current price × remaining qty) − (weighted avg cost × remaining qty)
- Trading commissions are subtracted from P&L for accuracy

### 5.2 Weighted Average Cost
- Computed from remaining FIFO lots (after sells are matched)
- `weightedAvgCost = Σ(lot.qty × lot.price) / Σ(lot.qty)` across all unconsumed lots

### 5.3 Holdings Sorting
- By name (A-Z), by value (high-low), by P&L amount, by P&L percentage

## 6. Architecture — MVI

```
Intent (user/system action)
  → Processor (async intent handler, updates state)
    → State (@Observable, single source of truth)
      → View (SwiftUI, renders state)
```

**Per feature:**
- `*Intent.swift` — enum of all possible user and system actions
- `*State.swift` — `@Observable` state object holding all view data
- `*Processor.swift` — receives intents, performs side effects (API calls, DB queries), mutates state
- `*View.swift` — pure SwiftUI view driven by state, sends intents back to processor

## 7. Data Models

### 7.1 Persisted (SwiftData `@Model`)

**Trade**
| Field | Type | Notes |
|---|---|---|
| `binanceTradeId` | `Int64` | Binance trade ID |
| `symbol` | `String` | e.g. "BTCUSDT" |
| `asset` | `String` | e.g. "BTC" (base asset, extracted from symbol) |
| `price` | `Double` | Price per unit in USDT |
| `quantity` | `Double` | Amount of base asset |
| `quoteQuantity` | `Double` | Total USDT value (price × qty) |
| `commission` | `Double` | Trading fee amount |
| `commissionAsset` | `String` | Fee currency (e.g. "BNB") |
| `timestamp` | `Date` | Trade execution time |
| `isBuyer` | `Bool` | true = buy, false = sell |
| `orderId` | `Int64` | Binance order ID |

Unique constraint: (`binanceTradeId`, `symbol`)

**SyncMetadata**
| Field | Type | Notes |
|---|---|---|
| `symbol` | `String` | Unique — e.g. "BTCUSDT" |
| `lastTradeId` | `Int64` | For incremental sync via `fromId` |
| `lastSyncDate` | `Date` | When this symbol was last synced |

### 7.2 Computed (plain Swift structs — not persisted)

**Holding** — per-coin aggregated position
- `asset`, `totalQuantity`, `weightedAvgBuyPrice`, `totalInvestedUSDT`, `currentPrice`, `currentValueUSDT`, `unrealizedPnL`, `unrealizedPnLPercent`, `realizedPnL`

**PortfolioSummary** — aggregate across all holdings
- `totalInvestedUSDT`, `totalCurrentValueUSDT`, `totalUnrealizedPnL`, `totalRealizedPnL`, `overallPnLPercent`

**Kline** — candlestick data for charts
- `openTime`, `open`, `high`, `low`, `close`, `volume`, `closeTime`

## 8. Binance API Integration

### 8.1 Endpoints

| Endpoint | Auth | Purpose | Rate Weight |
|---|---|---|---|
| `GET /api/v3/account` | HMAC-SHA256 | Discover assets with non-zero balances | 20 |
| `GET /api/v3/myTrades?symbol=X` | HMAC-SHA256 | Fetch trade history per symbol | 20 |
| `GET /api/v3/ticker/price` | None (public) | Current prices for held assets | 4 |
| `GET /api/v3/klines?symbol=X` | None (public) | Candlestick data for coin detail chart | 2 |

### 8.2 Authentication
- HMAC-SHA256 signature via `CryptoKit`
- API key sent as `X-MBX-APIKEY` header
- Query params sorted alphabetically, signed with secret
- `timestamp` and `recvWindow` included in signed params

### 8.3 Sync Strategy
1. Call `/account` with `omitZeroBalances=true` → discover held asset names
2. For each asset, construct USDT pair (e.g. BTC → BTCUSDT)
3. Call `/myTrades` per symbol; use `fromId` from `SyncMetadata` for incremental sync
4. Paginate: if 1000 results returned, repeat with `fromId = lastTradeId + 1`
5. Call `/ticker/price` with all held symbols for current prices
6. Persist new trades in SwiftData, update `SyncMetadata`

### 8.4 Security
- API key and secret stored in **iOS Keychain** (Security framework)
- Service identifier: `com.fahied.EasyCrypto.binance`
- Never logged, never stored in SwiftData or UserDefaults
- Read-only API permissions sufficient (no trade/withdraw access needed)

## 9. Design Language

- **iOS 26 Liquid Glass**: `.glassEffect()` on cards and containers
- **Glass tab bar**: leveraging system iOS 26 tab styling
- **Dark mode default** (aligns with crypto app conventions)
- **Semantic colors**: green for profit, red for loss, system gray for neutral
- **SF Symbols**: `chart.pie.fill` (Portfolio), `bitcoinsign.circle.fill` (Holdings), `clock.fill` (History), `gearshape.fill` (Settings)

### Reusable Design Components
| Component | Purpose |
|---|---|
| `GlassCard` | Frosted glass card container with `.glassEffect()` |
| `PnLLabel` | Colored P&L display (green/red) with directional arrow |
| `MetricCard` | Glass card for a single KPI (label + value) |
| `TradeRowView` | Trade list row (date, side, price, qty, total USDT) |

## 10. Project Structure

```
EasyCrypto/
├── EasyCryptoApp.swift              — App entry, ModelContainer setup
├── ContentView.swift                — TabView shell
├── Core/
│   ├── Architecture/
│   │   └── MVI.swift                — Base protocols & Processor class
│   ├── Models/
│   │   ├── Trade.swift              — @Model: persisted trade record
│   │   ├── SyncMetadata.swift       — @Model: sync state per symbol
│   │   ├── Holding.swift            — Computed per-coin position
│   │   ├── PortfolioSummary.swift   — Computed portfolio aggregate
│   │   └── Kline.swift              — Chart candlestick data
│   ├── Networking/
│   │   ├── BinanceAPIClient.swift   — URLSession + HMAC signing
│   │   └── BinanceModels.swift      — API response Decodables
│   └── Services/
│       ├── KeychainService.swift    — Secure credential storage
│       ├── TradeImportService.swift — Orchestrates full sync flow
│       ├── PriceService.swift       — Batch price fetching
│       └── FIFOCalculator.swift     — FIFO cost basis engine
├── Features/
│   ├── Portfolio/
│   │   ├── PortfolioIntent.swift
│   │   ├── PortfolioState.swift
│   │   ├── PortfolioProcessor.swift
│   │   └── PortfolioView.swift
│   ├── Holdings/
│   │   ├── HoldingsIntent.swift
│   │   ├── HoldingsState.swift
│   │   ├── HoldingsProcessor.swift
│   │   ├── HoldingsListView.swift
│   │   ├── CoinDetailIntent.swift
│   │   ├── CoinDetailState.swift
│   │   ├── CoinDetailProcessor.swift
│   │   └── CoinDetailView.swift
│   ├── TradeHistory/
│   │   ├── TradeHistoryIntent.swift
│   │   ├── TradeHistoryState.swift
│   │   ├── TradeHistoryProcessor.swift
│   │   └── TradeHistoryView.swift
│   └── Settings/
│       ├── SettingsIntent.swift
│       ├── SettingsState.swift
│       ├── SettingsProcessor.swift
│       └── SettingsView.swift
└── DesignSystem/
    ├── GlassCard.swift
    ├── PnLLabel.swift
    ├── MetricCard.swift
    └── TradeRowView.swift
```

## 11. Apple Frameworks Used

| Framework | Purpose |
|---|---|
| SwiftUI | UI layer |
| SwiftData | Local persistence (Trade, SyncMetadata) |
| Swift Charts | Line chart in Coin Detail |
| CryptoKit | HMAC-SHA256 for Binance API signing |
| Security | iOS Keychain for API key/secret storage |
| Foundation / URLSession | HTTP networking (async/await) |
| os | Structured logging (`os.Logger`) |
| [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | Dependency injection for all services (testing & previews) |

## 12. Testing Strategy

| Test Suite | Framework | Coverage |
|---|---|---|
| `FIFOCalculatorTests` | Swift Testing | Simple sell, partial sell, DCA averaging, full close, edge cases |
| `BinanceAPIClientTests` | Swift Testing | HMAC signature correctness, URL construction, error parsing |
| `HoldingCalculationTests` | Swift Testing | Weighted average cost, P&L accuracy across scenarios |
| SwiftData integration | Swift Testing | Model persistence, queries, sync metadata updates |

## 13. Acceptance Criteria

1. Settings: enter API key → Test Connection → green success indicator
2. Initial sync: pull-to-refresh on Portfolio → trades imported → holdings appear with correct avg cost
3. P&L accuracy: manually verify 1-2 coins — invested USDT matches sum of buy trades, current value = current price × qty
4. FIFO sell: realized P&L correctly matches earliest buy lots consumed
5. Coin detail: tap a holding → summary card, chart loads with selectable intervals, trade list is complete
6. Trade history: all trades chronological, filter by coin works
7. Incremental sync: second pull-to-refresh only fetches new trades (SyncMetadata.lastTradeId advances)
8. Design: glass effect cards render correctly, tab bar uses iOS 26 styling
9. All unit tests green

## 14. Architectural Decisions Record

| # | Decision | Rationale |
|---|---|---|
| ADR-1 | USDT pairs only | User trades exclusively in USDT; simplifies price display and P&L math |
| ADR-2 | Single Binance account | No multi-account need identified; reduces complexity |
| ADR-3 | FIFO cost basis | Industry-standard method for realized P&L; matches tax reporting conventions |
| ADR-4 | Weighted average for display | Single avg buy price is easier to understand than showing all lots |
| ADR-5 | Asset auto-discovery via `/account` | Avoids requiring user to manually list coins; only reads asset names from balance endpoint |
| ADR-6 | swift-dependencies for DI | Enables testable processors via `@Dependency`; struct-with-closures pattern replaces protocols; preview/test values built-in |
| ADR-7 | iOS 26+ minimum | Enables liquid glass design, latest SwiftData/SwiftUI APIs, Swift 6 concurrency defaults |
| ADR-8 | Keychain for credentials | Most secure local storage on iOS; not SwiftData or UserDefaults |
| ADR-9 | MVI architecture | Unidirectional data flow; clear separation of state, intents, and side effects; testable processors |
| ADR-10 | Commissions in P&L | Subtracting trading fees gives accurate net P&L |
| ADR-11 | Line chart (not candlestick) | Swift Charts handles line charts natively; candlestick can be added later |
| ADR-12 | Manual refresh only | MVP scope — no WebSocket or background refresh; user controls when data updates |

## 15. Open Questions

1. **Portfolio vs Holdings tab overlap**: Both tabs display holdings lists. Consider merging into one tab (summary metrics at top + holdings list below) to reduce redundancy and free a tab for future features (e.g. Alerts, Watchlist). **Recommendation: merge.**

2. **Future scope**: Real-time price updates via WebSocket, price alerts, multiple exchange support, export to CSV for tax reporting.

## 16. Related Documents

- [Docs/TECHNICAL-DIRECTION.md](Docs/TECHNICAL-DIRECTION.md) — detailed technical decisions (DI patterns, concurrency, error handling, logging, formatting)
