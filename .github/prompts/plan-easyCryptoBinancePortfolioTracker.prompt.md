# Plan: EasyCrypto — Binance Portfolio Tracker (iOS 26)

Build a 4-tab iOS 26 app that imports spot trade history from Binance API, displays portfolio overview with clear USDT-denominated P&L, per-coin holdings with weighted average cost, FIFO-based realized P&L on sells, trade history, and coin detail with chart. Uses MVI architecture, SwiftData persistence, iOS 26 liquid glass design, and Keychain for API key storage. Manual refresh only — pull-to-refresh syncs trades + prices in one action.

---

### Required Skills — Read Before Implementing

Before starting any phase, **read and follow** the relevant `.agents/skills` in this repo. These contain project-specific best practices and rules that must be applied.

| Skill | Path | When to use |
|---|---|---|
| **swiftdata-pro** | `.agents/skills/swiftdata-pro/SKILL.md` | Steps 1.1, 1.5, 3.2, and any SwiftData model/query work. Follow its core rules, predicate safety, and indexing guidelines. |
| **swift-concurrency** | `.agents/skills/swift-concurrency/SKILL.md` | All networking, services, and processor code. Follow its actor isolation patterns, `nonisolated` guidance, and `Sendable` rules. |
| **swift-testing-expert** | `.agents/skills/swift-testing-expert/SKILL.md` | Phase 5 and all test writing. Follow its `#expect`/`#require` macros, `@Test`/`@Suite` structure, parameterized test patterns. |
| **figma-to-mvi** | `.agents/skills/figma-to-mvi/SKILL.md` | Steps 2.1–2.5 (MVI feature layer). Follow its intent modeling, state modeling, and processor side-effect patterns. |

Also consult:
- `Project-Brief.md` — scope, acceptance criteria, ADRs
- `Docs/TECHNICAL-DIRECTION.md` — detailed technical decisions (DI with swift-dependencies, error handling, logging, formatting, concurrency model)

---

### Phase 1: Foundation (Core Infrastructure)

**Step 1.1 — SwiftData Models** *(parallel with 1.2–1.4)*
- `Trade` (`@Model`) — binanceTradeId, symbol, asset, price, quantity, quoteQuantity, commission, commissionAsset, timestamp, isBuyer, orderId. Unique on (binanceTradeId, symbol).
- `SyncMetadata` (`@Model`) — symbol (unique), lastTradeId, lastSyncDate
- `Holding` (plain struct) — computed per-coin position: asset, totalQuantity, weightedAvgBuyPrice, totalInvestedUSDT, currentPrice, currentValueUSDT, unrealizedPnL, unrealizedPnLPercent, realizedPnL
- `PortfolioSummary` (plain struct) — aggregated totals across all holdings
- `Kline` (plain struct) — candlestick data for charts

**Step 1.2 — Keychain Service** *(parallel with 1.1, 1.3, 1.4)*
- Save/load/delete Binance API key + secret using Security framework
- Service ID: `com.fahied.EasyCrypto.binance`

**Step 1.3 — Binance API Client** *(parallel with 1.1, 1.2, 1.4)*
- HMAC-SHA256 signing via `CryptoKit`, `URLSession` + `async/await`
- Authenticated: `GET /api/v3/account` (discover assets), `GET /api/v3/myTrades` (trade history per symbol)
- Public: `GET /api/v3/ticker/price` (current prices), `GET /api/v3/klines` (chart data)
- Proper error handling for rate limits, auth failures, network errors

**Step 1.4 — FIFO P&L Calculator** *(parallel with 1.1–1.3)*
- Maintains FIFO queue of buy lots per asset
- On sell: consumes earliest lots first, calculates realized P&L
- Outputs: remaining lots, weighted average cost, total remaining qty, realized P&L

**Step 1.5 — Trade Import Service** *(depends on 1.1, 1.2, 1.3)*
- Calls `/account` with `omitZeroBalances=true` to auto-discover held assets
- For each asset, calls `/myTrades?symbol={ASSET}USDT` with pagination (`fromId` for incremental sync, max 1000 per call)
- Maps API responses → `Trade` SwiftData models, updates `SyncMetadata`

**Step 1.6 — Price Service** *(depends on 1.3)*
- Batch-fetches current USDT prices for all held assets via `/ticker/price`

---

### Phase 2: MVI Feature Layer *(depends on Phase 1; features parallel with each other)*

**Step 2.1 — Base MVI Types**
- `ViewState` protocol, `Intent` protocol, generic `@Observable` `Processor` class
- `func send(_ intent:)` dispatches to async handler, updates state

**Step 2.2 — Portfolio Tab** (overview + summary)
- Intents: `.refresh`, `.sortHoldings(by:)`
- State: summary metrics, holdings list, loading, error, last refresh date, sort criteria
- View: Glass metric cards (Total Invested, Current Value, Unrealized P&L %, Realized P&L) + scrollable holdings list + pull-to-refresh + sort picker

**Step 2.3 — Holdings Tab + Coin Detail** (per-coin deep dive)
- Holdings list: all coins with avg cost, current price, qty, P&L. Tap → detail.
- Coin Detail intents: `.loadDetail(asset)`, `.changeChartInterval`
- Coin Detail view: summary glass card + Swift Charts line chart (kline data) + scrollable trade list for that coin

**Step 2.4 — Trade History Tab** (all trades)
- Intents: `.loadHistory`, `.filterByCoin(String?)`
- View: filter chips at top, chronological trade list grouped by date, BUY (green) / SELL (red) side labels

**Step 2.5 — Settings Tab**
- Intents: `.saveApiKey`, `.deleteApiKey`, `.testConnection`, `.clearAllData`
- View: SecureField for API key/secret, Save/Delete/Test buttons, connection status indicator, sync stats, destructive Clear All Data with confirmation

---

### Phase 3: App Shell & Navigation *(depends on Phase 2)*

**Step 3.1** — `ContentView` → `TabView` with 4 tabs (Portfolio, Holdings, History, Settings) + iOS 26 glass tab bar
**Step 3.2** — `EasyCryptoApp` → configure `ModelContainer` with schemas, inject shared services
**Step 3.3** — Empty state / onboarding: no API key → direct to Settings; API key but no trades → prompt pull-to-refresh

---

### Phase 4: iOS 26 Design System *(parallel with Phase 2)*

- `GlassCard` — reusable `.glassEffect()` card modifier
- `PnLLabel` — green/red colored P&L with arrow indicators
- `MetricCard` — glass card for single metric (label + value)
- `TradeRowView` — reusable trade row (date, side, price, qty, total)
- Dark mode default, semantic profit/loss colors

---

### Phase 5: Testing *(start after Step 1.4, parallel with Phase 2)*

- `FIFOCalculatorTests` — simple sell, partial sell, DCA averaging, full close, edge cases
- `BinanceAPIClientTests` — HMAC signature correctness, URL construction
- `HoldingCalculationTests` — weighted average cost, P&L accuracy
- SwiftData integration tests with mock data

---

### Relevant Files
- `EasyCrypto/EasyCryptoApp.swift` — modify for ModelContainer + services
- `EasyCrypto/ContentView.swift` — replace with TabView
- `EasyCryptoTests/EasyCryptoTests.swift` — add business logic tests
- ~30 new files across `Core/`, `Features/`, `DesignSystem/`

---

### Folder Structure

```
EasyCrypto/
├── EasyCryptoApp.swift
├── ContentView.swift
├── Core/
│   ├── Architecture/
│   │   └── MVI.swift
│   ├── Models/
│   │   ├── Trade.swift
│   │   ├── SyncMetadata.swift
│   │   ├── Holding.swift
│   │   ├── PortfolioSummary.swift
│   │   └── Kline.swift
│   ├── Networking/
│   │   ├── BinanceAPIClient.swift
│   │   └── BinanceModels.swift
│   └── Services/
│       ├── KeychainService.swift
│       ├── TradeImportService.swift
│       ├── PriceService.swift
│       └── FIFOCalculator.swift
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

---

### Binance API Endpoints Used

| Endpoint | Auth | Purpose | Weight |
|---|---|---|---|
| `GET /api/v3/account` | HMAC | Discover assets with non-zero balances | 20 |
| `GET /api/v3/myTrades?symbol=X` | HMAC | Fetch trade history per symbol | 20 |
| `GET /api/v3/ticker/price` | None | Fetch current prices for held assets | 4 |
| `GET /api/v3/klines?symbol=X` | None | Candlestick data for coin detail chart | 2 |

**Sync Strategy:**
1. Call `/account` with `omitZeroBalances=true` to discover held assets
2. For each asset, construct USDT pair symbol (e.g. BTC → BTCUSDT)
3. Call `/myTrades` per symbol; use `fromId` from `SyncMetadata` for incremental sync
4. Paginate: if 1000 results returned, call again with `fromId = lastTradeId + 1`
5. Call `/ticker/price` with all held symbols for current prices
6. Persist trades in SwiftData, update SyncMetadata

---

### Verification
1. Unit tests green: FIFO calculator, HMAC signature, holding computation
2. Settings: enter API key → Test Connection → success
3. Initial sync: pull-to-refresh imports trades, holdings appear with correct avg cost
4. P&L check: manually verify 1-2 coins match expected USDT invested vs current value
5. FIFO sell accuracy: realized P&L matches expected FIFO against earliest buys
6. Coin detail: tap → summary card, chart renders, trade list correct
7. Trade history: chronological, filter by coin works
8. Incremental sync: second refresh only fetches new trades
9. Glass design: `.glassEffect()` on cards, glass tab bar

---

### Decisions
- USDT pairs only — non-USDT pairs ignored
- Single Binance account — no multi-account
- FIFO cost basis for realized P&L on sells
- Weighted average displayed as single avg buy price across remaining FIFO lots
- Asset auto-discovery via `/account` endpoint (only uses balance to learn asset names; actual holdings computed from trade history)
- Zero third-party deps: URLSession, CryptoKit, SwiftData, Swift Charts, Security framework
- iOS 26+ only: liquid glass, `@Observable`, Swift 6 concurrency

---

### Further Considerations — Please Review

1. **Portfolio vs Holdings tab overlap**: Both tabs show a list of held coins. Consider merging into one tab (summary at top + holdings list below), freeing a tab slot for future features. **Recommendation: merge.** Do you want to keep them separate or merge?

2. **Chart type**: Swift Charts supports line charts well but has limited candlestick support. **Recommendation: start with line chart**, iterate to candlestick later. Preference?

3. **Commission in P&L**: Should Binance trading commissions be subtracted from P&L calculations for accuracy? **Recommendation: yes.** Agree?
