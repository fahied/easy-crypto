# Technical Direction — EasyCrypto

> Living document capturing all technical decisions for the EasyCrypto iOS project.
> Last updated: May 2026

---

## 1. Platform & Toolchain

| Property | Decision | Notes |
|---|---|---|
| Minimum deployment | iOS 26 | Enables liquid glass, latest SwiftData, Swift 6 defaults |
| Swift version | 6.2 | Project configured with `SWIFT_APPROACHABLE_CONCURRENCY` enabled |
| Xcode | 26+ | Required for iOS 26 SDK |
| Package manager | Xcode-integrated SPM | Dependencies added via Xcode project's Package Dependencies, not a root `Package.swift` |

## 2. Dependencies

| Package | Version | Purpose |
|---|---|---|
| [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | Latest | Dependency injection for all services; testable, preview-friendly architecture |

**No other third-party dependencies.** All remaining needs are covered by Apple frameworks:

| Framework | Purpose |
|---|---|
| SwiftUI | UI layer |
| SwiftData | Local persistence (`Trade`, `SyncMetadata`) |
| Swift Charts | Line chart in Coin Detail screen |
| CryptoKit | HMAC-SHA256 for Binance API request signing |
| Security | iOS Keychain for API key/secret storage |
| Foundation / URLSession | HTTP networking (`async/await`) |
| os | Structured logging (`os.Logger`) |

## 3. Architecture — MVI

### 3.1 Pattern

```
User/System Action
  → Intent (enum)
    → Processor (@Observable, handles intents, performs side effects)
      → State (single source of truth, drives the view)
        → View (pure SwiftUI, sends intents back)
```

Unidirectional data flow. State is never mutated directly by views.

### 3.2 File Convention per Feature

```
Feature/
├── FeatureIntent.swift      — enum of all intents
├── FeatureState.swift        — @Observable state class
├── FeatureProcessor.swift    — intent handler + side effects
└── FeatureView.swift         — SwiftUI view
```

### 3.3 Processor Rules
- Processors are `@Observable` classes
- A single `func send(_ intent:)` entry point dispatches to async handlers
- Side effects (API calls, DB queries) happen inside the processor, never in the view
- State updates are always performed on `@MainActor`

## 4. Concurrency Model

| Decision | Rationale |
|---|---|
| Project default: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` | All types are `@MainActor` by default (Swift 6.2) |
| Networking & computation: `nonisolated` | `BinanceAPIClient`, `FIFOCalculator`, `PriceService`, and `TradeImportService` opt out of MainActor isolation to avoid blocking the UI thread |
| `SWIFT_APPROACHABLE_CONCURRENCY` enabled | Smoother Swift 6 adoption with approachable diagnostics |

### Rules
- Views and Processors stay on `@MainActor` (the default)
- Services and networking are explicitly `nonisolated` or use `nonisolated(unsafe)` only where truly required
- No `DispatchQueue` usage — use structured concurrency (`async let`, `TaskGroup`) exclusively
- Use `Task { }` in processors to bridge sync intent dispatch to async work

## 5. Dependency Injection — swift-dependencies

### 5.1 Scope
All services are registered as `@Dependency` keys:

| Dependency Key | Type | Isolation |
|---|---|---|
| `BinanceAPIClient` | struct (with closures) or protocol | `nonisolated` |
| `KeychainService` | struct (with closures) | `nonisolated` |
| `TradeImportService` | struct (with closures) | `nonisolated` |
| `PriceService` | struct (with closures) | `nonisolated` |
| `FIFOCalculator` | struct (with closures) | `nonisolated` |

### 5.2 Pattern
Follow the swift-dependencies "client" pattern:

```swift
// 1. Define the client struct
struct BinanceAPIClient: Sendable {
    var fetchAccount: @Sendable () async throws -> [BinanceBalance]
    var fetchMyTrades: @Sendable (_ symbol: String, _ fromId: Int64?) async throws -> [BinanceTrade]
    var fetchTickerPrices: @Sendable (_ symbols: [String]) async throws -> [BinanceTickerPrice]
    var fetchKlines: @Sendable (_ symbol: String, _ interval: String, _ limit: Int) async throws -> [Kline]
}

// 2. Register with DependencyKey
extension BinanceAPIClient: DependencyKey {
    static let liveValue = BinanceAPIClient(...)
    static let previewValue = BinanceAPIClient(...)  // returns mock data
    static let testValue = BinanceAPIClient(...)     // unimplemented
}

// 3. Consume in Processors
@Observable
class PortfolioProcessor {
    @ObservationIgnored
    @Dependency(BinanceAPIClient.self) var apiClient
}
```

### 5.3 Benefits
- **Tests**: swap to `testValue` (unimplemented by default, override per test)
- **Previews**: swap to `previewValue` (returns static mock data)
- **No protocols needed**: the struct-with-closures pattern replaces protocol-based DI

## 6. Data Layer — SwiftData

### 6.1 Models
Two `@Model` classes:

- **`Trade`** — persisted trade record (see Project Brief §7.1 for full schema)
- **`SyncMetadata`** — tracks last synced trade ID per symbol

### 6.2 Value Types
- All financial values stored as `Double` (prices, quantities, P&L)
- Sufficient precision for display purposes; no `Decimal`/`NSDecimalNumber` overhead

### 6.3 Schema Versioning
- **Not set up initially** — add `VersionedSchema` + `SchemaMigrationPlan` when the first schema migration is needed
- Until then, use the default schema with no migration plan

### 6.4 ModelContainer Setup
- Configured once in `EasyCryptoApp.swift`
- Injected via SwiftUI `.modelContainer()` modifier
- Schemas: `[Trade.self, SyncMetadata.self]`

### 6.5 Querying
- Views that need live query results use `@Query` where appropriate
- Processors use `ModelContext` for imperative fetches/inserts via `FetchDescriptor`
- No `@Query` outside SwiftUI views

## 7. Networking

### 7.1 Transport
- `URLSession.shared` with `async/await`
- No custom `URLSession` configuration unless rate limiting requires retry logic
- JSON decoding via `JSONDecoder` with `.convertFromSnakeCase` where applicable

### 7.2 Authentication
- HMAC-SHA256 signature via `CryptoKit`
- API key sent as `X-MBX-APIKEY` HTTP header
- All signed request parameters sorted alphabetically, concatenated as query string, signed with secret
- `timestamp` (epoch ms) and `recvWindow` included in signed params

### 7.3 Error Handling
- Binance API errors decoded as `BinanceAPIError` (code + message)
- Network errors, HTTP status codes, and API errors mapped to a unified `BinanceError` enum
- Rate limit errors (HTTP 429) surfaced clearly to the user

## 8. Error Handling & UX

| Scenario | UX Pattern |
|---|---|
| Initial load failure (no cached data) | Inline error state replacing content, with retry button |
| Refresh failure (cached data exists) | Banner/toast at top, auto-dismisses after 4 seconds |
| API key invalid / expired | Inline error with "Go to Settings" action |
| Rate limited (HTTP 429) | Banner showing "Rate limited, try again in X seconds" |
| Network offline | Inline error state with retry; show cached data if available |
| Sync in progress | Loading indicator (pull-to-refresh spinner or progress) |

### Error Type Hierarchy
```swift
enum BinanceError: Error, LocalizedError {
    case invalidCredentials
    case rateLimited(retryAfterSeconds: Int?)
    case apiError(code: Int, message: String)
    case networkError(underlying: Error)
    case decodingError(underlying: Error)
    case noCredentialsConfigured
}
```

## 9. Logging

### 9.1 Framework
Apple's `os.Logger` with structured subsystem/category.

### 9.2 Subsystem
`com.fahied.EasyCrypto`

### 9.3 Categories

| Category | Usage |
|---|---|
| `networking` | API request/response logging (URLs, status codes, timing — never log secrets) |
| `sync` | Trade import progress, pagination, asset discovery |
| `fifo` | FIFO lot matching, P&L calculation steps |
| `keychain` | Credential save/load/delete operations (log events, never values) |
| `ui` | View lifecycle, intent dispatch (debug-level only) |

### 9.4 Rules
- **Never log API keys, secrets, or full request signatures**
- Log request URLs with query params redacted where sensitive
- Use `.debug` for verbose/tracing, `.info` for sync progress, `.error` for failures
- Logger instances are `static let` per file or service

## 10. Formatting & Display

### 10.1 Currency
- All monetary values displayed in USDT
- **2 decimal places** for all USDT values (e.g. `1,234.56 USDT`)
- Use `NumberFormatter` or `.formatted(.number.precision(.fractionLength(2)))` for consistent output
- Thousands separator enabled

### 10.2 Dates
- Use `.formatted()` with **relative style** (e.g. "2 hours ago", "yesterday")
- For trade history rows: relative for trades within the last 24 hours, formatted date for older

### 10.3 P&L Colors
- **Profit**: system green (`Color.green`)
- **Loss**: system red (`Color.red`)
- **Neutral / zero**: system secondary label color
- Directional arrows: `▲` for profit, `▼` for loss

## 11. Preview Data Strategy

- **In-memory SwiftData `ModelContainer`** seeded with sample trades
- `ModelConfiguration(isStoredInMemoryOnly: true)` for all previews
- Sample data covers: multiple coins, buy + sell trades, DCA scenarios, varying P&L
- Located in a `PreviewContent/` folder or `#Preview` blocks with inline seeding

## 12. Refresh Behavior

- **Pull-to-refresh only** (`.refreshable` modifier)
- No toolbar button, no floating action button, no background refresh
- Single action syncs both new trades AND latest prices
- Loading state shown via system pull-to-refresh spinner

## 13. UI Design — iOS 26 Liquid Glass

### 13.1 Design Tokens
- Use `.glassEffect()` modifier on metric cards, summary cards, and containers
- Follow Apple HIG for iOS 26 glass design language
- Tab bar uses system default glass styling (no custom glass override on tab bar)

### 13.2 Reusable Components

| Component | File | Purpose |
|---|---|---|
| `GlassCard` | `DesignSystem/GlassCard.swift` | Container ViewModifier applying `.glassEffect()` |
| `PnLLabel` | `DesignSystem/PnLLabel.swift` | Colored P&L text with directional arrow |
| `MetricCard` | `DesignSystem/MetricCard.swift` | Single KPI card (title + value + optional subtitle) |
| `TradeRowView` | `DesignSystem/TradeRowView.swift` | Reusable trade list row |

### 13.3 Dark Mode
- App supports both light and dark mode
- Dark mode is the expected primary usage (crypto app convention)
- No forced color scheme — respect system setting

## 14. Testing Strategy

### 14.1 Framework
- **Swift Testing** (already configured in the project)
- `#expect` / `#require` macros, `@Test` attributes, `@Suite` for grouping
- No XCTest for new tests

### 14.2 Dependency Overrides in Tests
Using swift-dependencies `withDependencies`:

```swift
@Test func portfolioRefreshComputesHoldings() async {
    await withDependencies {
        $0[BinanceAPIClient.self].fetchMyTrades = { _, _ in mockTrades }
        $0[BinanceAPIClient.self].fetchTickerPrices = { _ in mockPrices }
    } operation: {
        let processor = PortfolioProcessor()
        await processor.send(.refresh)
        #expect(processor.state.holdings.count == 3)
    }
}
```

### 14.3 Test Categories

| Suite | Focus |
|---|---|
| `FIFOCalculatorTests` | FIFO lot matching: simple sell, partial sell, DCA, full close, edge cases |
| `BinanceAPIClientTests` | HMAC signature generation, URL construction, error decoding |
| `HoldingCalculationTests` | Weighted average cost, P&L accuracy |
| `ProcessorTests` | Intent handling with mocked dependencies |
| `SwiftDataTests` | Model persistence, unique constraints, fetch descriptors |

## 15. Security Considerations

| Concern | Mitigation |
|---|---|
| API key/secret storage | iOS Keychain only; never UserDefaults, SwiftData, or files |
| Logging sensitive data | Logger rules prohibit logging keys, secrets, or signatures |
| Network transport | HTTPS only (Binance API enforces TLS) |
| API permissions | Only read-only permissions required; app never sends trade/withdraw requests |
| Input validation | API key format validated before saving; secret never displayed after entry |

## 16. Decisions Not Yet Made

These will be decided during implementation when more context is available:

| Topic | Status | Trigger |
|---|---|---|
| SwiftData schema versioning | Deferred | First schema change |
| Candlestick chart | Deferred | After evaluating Swift Charts line chart |
| Portfolio/Holdings tab merge | Open question | During UI implementation |
| Background refresh | Out of scope | Future iteration |
| Multi-exchange support | Out of scope | Future iteration |
| CSV export | Out of scope | Future iteration |
