# swift-dependencies

Point-Free's dependency injection framework for Swift. Use this skill whenever adding, registering, or using dependencies in a Swift project.

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.1")
]
```

Or add via Xcode: **File → Add Package Dependencies** and paste the URL above.

Import in any file:

```swift
import Dependencies
```

### Integration note

This skill covers SPM-based projects. If using Xcode without a `Package.swift`, add the `Dependencies` product via Xcode's SPM integration instead.

## Core Concept

Replace uncontrolled globals (`Date()`, `UUID()`, `Task.sleep`, `DispatchQueue.main.async`, network clients, storage access) with `@Dependency`-injected values. This makes every side effect controllable — in production, in SwiftUI previews, and in tests.

## The @Dependency Property Wrapper

Declare dependencies on any `@MainActor` class (typically Processors or ViewModels):

```swift
@MainActor
final class FeatureProcessor: Processor {
  // KeyPath form — most common
  @Dependency(\.apiClient) private var apiClient
  @Dependency(\.calendar) private var calendar
  @Dependency(\.date.now) private var now
  @Dependency(\.continuousClock) private var clock
  @Dependency(\.mainQueue) private var mainQueue

  // Type form — for TestDependencyKey protocol-based deps
  @Dependency(CredentialStoreProtocol.self) private var credentialStore

  func process(_ intent: FeatureIntent) async {
    switch intent {
    case .refresh:
      let data = await apiClient.fetchData()
      // ...
    }
  }
}
```

**Rules:**
- Only inject into Processors or ViewModels (the only classes that hold business logic). Views never hold dependencies directly.
- Always prefix with `private` — the dependency is an implementation detail.
- When used inside an `@Observable` class (State), annotate with `@ObservationIgnored`:
  ```swift
  @ObservationIgnored
  @Dependency(\.continuousClock) var clock
  ```
- Static `@Dependency` properties lazily capture their values at first access site — avoid them.

## Registering Custom Dependencies

Three steps for each dependency:

### Step 1: Define the protocol

```swift
// Services/Networking/APIClient.swift
protocol APIClientProtocol: Sendable {
  func fetchAccountInfo() async throws -> AccountInfo
  func fetchRecords() async throws -> [Record]
  func fetchCurrentPrice(for symbol: String) async throws -> Price
}

// Make it usable as a @Dependency key via TestDependencyKey
extension APIClientProtocol: TestDependencyKey {}
```

### Step 2: Register in DependencyValues

```swift
// Core/Dependencies/DependencyValues.swift
import Dependencies

extension DependencyValues {
  var apiClient: APIClientProtocol {
    get { self[APIClientProtocol.self] }
    set { self[APIClientProtocol.self] = newValue }
  }

  var credentialStore: CredentialStoreProtocol {
    get { self[CredentialStoreProtocol.self] }
    set { self[CredentialStoreProtocol.self] = newValue }
  }

  var dataStore: DataStoreProtocol {
    get { self[DataStoreProtocol.self] }
    set { self[DataStoreProtocol.self] = newValue }
  }

  var logger: Logger {
    get { self[Logger.self] }
    set { self[Logger.self] = newValue }
  }

  // Calendar is built-in — no registration needed
  var calendar: Calendar {
    get { self[CalendarKey.self] }
    set { self[CalendarKey.self] = newValue }
  }
}

// Calendar is not Sendable in its raw form, so wrap it
private enum CalendarKey: DependencyKey, Sendable {
  static let liveValue = Calendar.current
  static func restoreValue(_ value: Calendar) -> Calendar { value }
  static func mutateValue(_ value: inout Calendar, mutation: (inout Calendar) -> Void) -> Calendar {
    var copy = value
    mutation(&copy)
    return copy
  }
}
```

### Step 3: Provide live values at app startup

```swift
// AppEntry.swift
import Dependencies

@main
struct MyApp: App {
  init() {
    // Register all live dependencies once at app launch
    Self._registerDependencies()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.apiClient, apiClient)
        .environment(\.credentialStore, credentialStore)
    }
  }

  @Dependency(\.apiClient) private var apiClient
  @Dependency(\.credentialStore) private var credentialStore

  private static func _registerDependencies() {
    @Dependency(\.apiClient) var apiClient
    @Dependency(\.credentialStore) var credentialStore

    // Live values — the real implementations
    withDependencies {
      $0.apiClient = APIClient.live()
      $0.credentialStore = CredentialStore.live()
    } operation: {
      // This sets the initial cached values
    }
  }
}
```

## Providing Live Implementations

Each service provides a static `live()` factory:

```swift
// Services/Networking/APIClient.swift
struct APIClient: APIClientProtocol, Sendable {
  let apiKey: String
  let apiSecret: String

  static func live() -> Self {
    @Dependency(\.credentialStore) var credentialStore
    let credentials = try! credentialStore.retrieveCredentials()
    return Self(apiKey: credentials.key, apiSecret: credentials.secret)
  }

  func fetchAccountInfo() async throws -> AccountInfo {
    // Real network call with signing logic
  }

  func fetchRecords() async throws -> [Record] {
    // Real network call
  }

  func fetchCurrentPrice(for symbol: String) async throws -> Price {
    // Real network call
  }
}
```

```swift
// Services/Storage/CredentialStore.swift
struct CredentialStore: CredentialStoreProtocol, Sendable {
  static func live() -> Self { Self() }

  func retrieveCredentials() throws -> (key: String, secret: String) {
    // Secure storage lookup (Keychain, etc.)
  }

  func store(_ value: String, for key: String) throws { }
  func retrieve(for key: String) throws -> String { }
  func delete(for key: String) throws { }
}
```

## Scopes and Lifetime Management

### The `withDependencies` function

Scopes an override to a specific operation:

```swift
// Override for a single operation
try await withDependencies {
  $0.apiClient = APIClient.mock()
  $0.date.now = Date(timeIntervalSinceReferenceDate: 1234567890)
} operation: {
  let result = try await someProcessor.process(.refresh)
  // dependencies revert after this block
}
```

### Scope (`.userInitiated`)

For user-initiated flows that should outlive a single operation:

```swift
// In a Processor handling a multi-step flow
func process(_ intent: FeatureIntent) async {
  switch intent {
  case .linkAccount:
    // Dependencies persist for the entire async flow, including across Task boundaries
    try await withDependencies(scope: .userInitiated) {
      $0.credentialStore = CredentialStore.ephemeral()
      await performOAuthFlow()
      await configureAPIClient()
    }
  }
}
```

### Available scopes

| Scope | Lifetime |
|---|---|
| `.none` (default) | One synchronous execution context. Escaping closures do NOT inherit overrides. `Task { }` DOES inherit. |
| `.userInitiated` | Propagates through `Task` and async continuations. Lives until all spawned tasks complete. |
| `.self` | Tied to an object's lifetime. Override lives as long as the object is retained. |

### Preparation Mode (advanced)

For initializing dependencies before first use:

```swift
// Call at app startup
DependencyValues.prepare {
  $0.apiClient = APIClient.live()
  $0.credentialStore = CredentialStore.live()
}
```

## Testing with Mock Dependencies

### Test trait (recommended — Swift Testing framework)

```swift
import Testing
import Dependencies

@Suite("FeatureProcessor Tests")
struct FeatureProcessorTests {
  @Test(.dependencies {
    $0.apiClient = .mock(
      fetchRecords: { [
        Record.sample1,
        Record.sample2,
        Record.sample3,
      ] }
    )
    $0.date.now = Date(timeIntervalSinceReferenceDate: 1234567890)
    $0.continuousClock = .immediate
  })
  func refresh_populatesStateWithRecords() async throws {
    let processor = FeatureProcessor()
    try await processor.process(.refresh)
    #expect(processor.items.count == 3)
    #expect(processor.items.first?.id == "record-1")
  }
}
```

### Mock factories

```swift
extension APIClientProtocol {
  static func mock(
    fetchAccountInfo: @escaping () async throws -> AccountInfo = { .mock() },
    fetchRecords: @escaping () async throws -> [Record] = { [] },
    fetchCurrentPrice: @escaping (String) async throws -> Price = { _ in .mock() }
  ) -> Self where Self: TestDependencyKey {
    MockAPIClient(
      fetchAccountInfo: fetchAccountInfo,
      fetchRecords: fetchRecords,
      fetchCurrentPrice: fetchCurrentPrice
    )
  }
}

struct MockAPIClient: APIClientProtocol, Sendable {
  let fetchAccountInfo: () async throws -> AccountInfo
  let fetchRecords: () async throws -> [Record]
  let fetchCurrentPrice: (String) async throws -> Price
}
```

### XCTest (legacy)

```swift
func testRefresh() async throws {
  let processor = FeatureProcessor()
  try await withDependencies {
    $0.apiClient = APIClient.mock(
      fetchRecords: { [.sample1] }
    )
    $0.date.now = Date(timeIntervalSinceReferenceDate: 1234567890)
  } operation: {
    try await processor.process(.refresh)
  }
  #expect(processor.items.count == 1)
}
```

## SwiftUI Previews

```swift
#Preview(traits: .dependencies {
  $0.apiClient = .mock(
    fetchRecords: { [.sample1, .sample2] }
  )
  $0.continuousClock = .immediate
}) {
  FeatureView()
    .environment(FeatureProcessor())
}
```

The `.dependencies` preview trait ensures the override applies only in Xcode previews, not on device.

## Dependency Planning

Use this table to plan which dependencies a project needs:

| Dependency | Protocol | Live Implementation | Mock Strategy |
|---|---|---|---|
| `apiClient` | `APIClientProtocol` | `APIClient.live()` — signed network requests | Mock returning fixture records |
| `credentialStore` | `CredentialStoreProtocol` | `CredentialStore.live()` — Keychain/secure storage | Mock with in-memory store |
| `dataStore` | `DataStoreProtocol` | `DataStore.live()` — persistence-backed | Mock with in-memory array |
| `calendar` | (built-in `Calendar`) | `Calendar.current` | Fixed date calendar |
| `logger` | `Logger` | `Logger(subsystem: "...", category: "...")` | No-op logger |
| `continuousClock` | (built-in `ContinuousClock`) | Live — real async timing | `.immediate` — collapses all delays |
| `date.now` | (built-in `Date`) | Live — system date | Fixed `Date` |
| `uuid` | (built-in `UUID`) | Live — random UUIDs | `.incrementing` — predictable sequence |
| `mainQueue` | (built-in `DispatchQueue`) | `.main` | Immediate dispatch |

## General Rules

1. **Inject only into Processors or ViewModels** — Views receive dependencies via the Processor, not directly.
2. **One file per dependency registration group** — a single `DependencyValues.swift` holds all `DependencyValues` extensions.
3. **Each service has a `live()` static factory** — uses `@Dependency` internally to get its own prerequisites.
4. **Every dependency needs a mock** — use `TestDependencyKey` conformance and mock factories.
5. **Never access uncontrolled globals directly** — always route through `@Dependency`:
   - `Date()` → `@Dependency(\.date.now)`
   - `UUID()` → `@Dependency(\.uuid)()`
   - `Task.sleep` → `@Dependency(\.continuousClock).sleep()`
   - `DispatchQueue.main.async` → `@Dependency(\.mainQueue).schedule {}`
6. **Use `.userInitiated` scope for async flows** that span multiple `Task` boundaries (e.g., OAuth, background sync).
7. **Reset cache between tests** — the library handles this automatically via test observer, but verify in CI.
8. **SPM or Xcode** — add the `Dependencies` product via your project's package management.

## What NOT to do

- Don't use `@Dependency` on `@State` or `@Binding` properties — they're value types, not reference types.
- Don't register dependencies inside feature code — all registration lives in `DependencyValues.swift`.
- Don't use `.self` scope for short-lived operations — it over-provisions memory.
- Don't share `@Dependency` properties between Processors — each Processor declares its own.
- Don't forget `@ObservationIgnored` on `@Dependency` inside `@Observable` State classes.

## Troubleshooting

**"Dependency was accessed but never prepared"** — A dependency value is being read before its `liveValue`/`testValue` is resolved. Ensure `live()` is called at app startup.

**"Dependency was mutated during lifetime"** — A dependency that should be constant (has no `restoreValue`/`mutateValue`) was mutated mid-flight. Add `restoreValue` and `mutateValue` to the `DependencyKey` conformance for mutable dependencies.

**Preview crashes** — Make sure every dependency used by the feature has a `previewValue` or is overridden via `.dependencies` in the preview. Without a preview value, the live implementation runs (which may fail in a preview context, e.g., Keychain).

**Tests flaky due to async** — Use `.immediate` clock and pin `date.now` to eliminate timing flakiness.

## Sources

- [Point-Free swift-dependencies Repository](https://github.com/pointfreeco/swift-dependencies)
- [swift-dependencies Documentation](https://swiftpackageindex.com/pointfreeco/swift-dependencies/latest/documentation/dependencies)
- [Point-Free Dependencies Series](https://www.pointfree.co/collections/dependencies)
