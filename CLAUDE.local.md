# EasyCrypto — Local Claude Instructions

<!-- This file supplements the canonical ARRIVE governance in CLAUDE.md. It is not synced by `arrive sync agent-rules`. -->

## Project Identity

EasyCrypto is a **read-only Binance spot + margin portfolio tracker** for iOS 26+, built with SwiftUI, SwiftData, and Swift 6.2. It imports trade history via the Binance API and presents a USDT-denominated view of holdings, FIFO-based P&L, and on-device AI insights. Data stays on device — no trading, no WebSocket, no cloud.

- **Bundle ID**: `com.fahied.EasyCrypto`
- **Language**: Swift 6.2, `@MainActor` default, `nonisolated` for networking/services
- **DI**: `swift-dependencies` (struct-with-closures, no protocols)
- **Architecture**: MVI — Intent → Processor → State → View

## How to Work Here

### TDD workflow — mandatory

Every change follows **tidy → test → implement** as separate commits:

- `tidy:` — preparatory refactoring (no behavior change)
- `test:` — failing test written first
- `feat:` — minimum code to make the test pass
- `fix:`, `docs:`, `chore:` — as appropriate

Tests use **Swift Testing** (`@Test`, `#expect`, `@Suite`) with BDD naming (`@Suite("Given ...")` / `@Test("When ..., then ...")`).
Coverage target: **≥ 80%** line coverage (≥ 90% for core business logic like `FIFOCalculator`).

### No third-party dependencies

Everything beyond Apple frameworks and `swift-dependencies` (via Xcode SPM) requires discussion. Use Apple frameworks directly — SwiftUI, SwiftData, Swift Charts, CryptoKit, Security, os.Logger, FoundationModels.

### Feature file convention

Every feature lives in `Features/<Name>/` with exactly four files:

```
FeatureNameIntent.swift    — enum of all intents
FeatureNameState.swift      — @Observable state class
FeatureNameProcessor.swift  — send(_:) dispatches to async handlers
FeatureNameView.swift       — pure SwiftUI view
```

Processors hold side effects (API calls, DB queries). Views never mutate state directly.

### Dependency injection

Services are consumed via `@Dependency` keys:

```swift
@ObservationIgnored @Dependency(BinanceAPIClient.self) var apiClient
```

Tests override with `withDependencies { }`. Previews get `previewValue`. Never use protocols for services.

## Source Map

```
EasyCrypto/
├── EasyCryptoApp.swift           — App entry, ModelContainer
├── ContentView.swift             — TabView shell
├── BackgroundTasks/              — PriceAlertRefresher, CandleAlertRefresher, InsightRefresher
├── Core/
│   ├── Architecture/MVI.swift    — Base protocols & Processor class
│   ├── Models/                   — @Model (SwiftData) + computed structs
│   ├── AI/                       — Foundation Model engine, chat, summarizer
│   └── Services/                 — BinanceAPIClient, FIFOCalculator, KeychainService, etc.
├── Features/
│   ├── Portfolio/                — Portfolio MVI
│   ├── Holdings/                 — Holdings + CoinDetail MVI
│   ├── TradeHistory/             — TradeHistory MVI
│   ├── Insights/                 — Insights MVI + AI chat
│   └── Settings/                 — Settings MVI + notification log
├── DesignSystem/                 — GlassCard, PnLLabel, MetricCard, TradeRowView, Theme
└── EasyCryptoUITests/            — UI tests
```

## ARRIVE Governance

- `arrive/` is the governance source — edit `arrive/agent-rules/core.md` then run `arrive sync agent-rules`
- Before any edit: identify impacted systems (`system.yaml` roots) and components (selectors)
- Advances live in `arrive/systems/easycrypto-core/advances/` — template-first via `arrive template render`
- Implementation plan: `arrive/implementation-plan.yaml` — check with `arrive plan show`
- Reviewability: Green ≤30, Yellow 31–60, Red >60 (split unless documented)
- Every advance needs a `## Check for Understanding` section — refresh it when the advance narrative changes

## Key Domain Concepts

| Concept | Detail |
|---|---|
| **FIFO cost basis** | Each buy creates a lot; sells consume earliest lots first. Realized P&L = proceeds − cost basis of consumed lots. |
| **TradingMode** | Abstraction (`.spot` / `.crossMargin` / `.isolatedMargin`) — margin support is additive, spot is unaffected. |
| **Sync strategy** | `/account` discovers assets → `/myTrades` per symbol (incremental via `fromId`) → `/ticker/price` for current prices. Pull-to-refresh does both in one action. |
| **AI Insights** | On-device only via Apple Foundation Models. Input is a bounded `TradeSummary` — raw trades never leave the device. Refreshed every ~4h. |

## Key Docs

- `docs/1.project-overview.md` — requirements, data models, acceptance criteria, ADRs, advance index
- `docs/2.technical-direction.md` — DI patterns, concurrency model, networking, logging, formatting, testing strategy, security

## Quick Commands

```bash
# Build & run
open EasyCrypto.xcodeproj   # Xcode 26+, iOS 26+ simulator

# Run unit tests headless (xcodebuild)
xcodebuild test \
  -project EasyCrypto.xcodeproj \
  -scheme EasyCrypto \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -derivedDataPath .build

# Run UI tests
xcodebuild test \
  -project EasyCrypto.xcodeproj \
  -scheme EasyCrypto \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:EasyCryptoUITests \
  -derivedDataPath .build

# ARRIVE governance
arrive plan show            # current implementation plan
arrive sync agent-rules     # after editing arrive/agent-rules/
arrive template render --kind advance --json   # scaffold an advance
```

> **Note**: If the scheme name differs, list them with `xcodebuild -list -project EasyCrypto.xcodeproj`. The simulator runtime must match what's installed on your machine — check with `xcrun simctl list runtimes`.
