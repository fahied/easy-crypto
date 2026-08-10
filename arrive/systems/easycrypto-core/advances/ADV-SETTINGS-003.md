---
advance:
  id: "ADV-SETTINGS-003"
  title: "Settings UI for trading mode selection — spot, cross-margin, and isolated-margin toggle"
  system: "easycrypto-core"
  primary_component: "settings"
  components: ["settings", "core-models"]
  started_at: "2026-08-07T09:00:00Z"
  implementation_completed_at: "2026-08-10T00:00:00Z"
  review_time_estimate_minutes: 30
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 15
  risk_flags: []
  evidence: []
  model_usage: []
  status: done
---

## Objective

Add a trading mode selector to the Settings screen so users can switch between spot,
cross-margin, and isolated-margin trading modes. The selection persists in
`AppStorage` and is propagated to `PortfolioProcessor`, `HoldingsProcessor`, and
`TradeHistoryProcessor`. Depends on ADV-CORE-MODELS-002 (TradingMode) and
ADV-PORTFOLIO-002 (portfolio margin mode).

## Behavioral Change

After this advance:

- SettingsView shows a "Trading Mode" section with three options:
  - Spot (default, blue)
  - Cross Margin (orange)
  - Isolated Margin (purple)
- The selector is a `Picker` with segmented style on iOS 26+ or a list of radio-style
  rows on earlier versions.
- The selected mode is persisted in `@AppStorage("selectedTradingMode")` so it survives
  app restarts.
- When the mode changes, a confirmation sheet appears explaining that the app will
  refresh to show the selected mode's data.
- On confirmation, the app triggers a portfolio refresh with the new mode.
- The current selection is shown as a small badge in the tab bar or navigation title
  (e.g., "Portfolio (Cross Margin)").
- If margin API calls fail after a mode switch, the user sees a non-blocking warning
  banner suggesting they switch back to Spot.

## Design Notes

- **AppStorage key**: `"selectedTradingMode"` with raw value fallback. On first launch
  (no stored value), defaults to `"spot"`.
- **Propagation via environment or shared state**: The selected mode flows to processors
  through the existing service injection pattern. `PortfolioProcessor` receives the mode
  in its `refresh()` call; `HoldingsProcessor` and `TradeHistoryProcessor` receive it
  via their `handle(_:)` methods.
- **Confirmation gate**: Switching from Spot to Margin (or vice versa) triggers a
  confirmation because the data source changes entirely. Switching between Cross and
  Isolated margin does not require confirmation (both are margin, same API tier).
- **Error banner**: If the margin API returns an error (e.g., margin not enabled on the
  account), a non-blocking banner appears: "Margin trading is not enabled on your
  account. Switch back to Spot." with a one-tap action to revert.

## Component Impact

- **settings** (`EasyCrypto/Features/Settings/SettingsView.swift`):
  - Add Trading Mode section with Picker
  - Add confirmation sheet for mode changes
  - Add error banner for margin API failures

- **app-shell** (`EasyCrypto/ContentView.swift`):
  - Read `selectedTradingMode` from AppStorage
  - Propagate to Portfolio/Holdings/TradeHistory processors on mode change
  - Update navigation title to show current mode

- **portfolio** (`EasyCrypto/Features/Portfolio/PortfolioProcessor.swift`):
  - Accept `TradingMode` from the caller (already planned in ADV-PORTFOLIO-002)

- **core-models** (`EasyCrypto/Core/Models/`):
  - No model changes needed — `TradingMode` enum already added in ADV-CORE-MODELS-002

## Out of Scope

- Per-symbol trading mode override (all symbols use the selected mode)
- Margin mode auto-detection based on API activity
- Trading mode sync across multiple devices (not planned)
- Margin mode onboarding tutorial

## Objective

Add a trading mode selector to the Settings screen so users can switch between spot,
cross-margin, and isolated-margin trading modes. The selection persists via the
`SettingsProcessor` using `UserDefaults` (not `@AppStorage`) and is read by other
features on launch.

## Behavioral Change

After this advance:

- SettingsView shows a "Trading Mode" section with a segmented `Picker` for Spot, Cross
  Margin, and Isolated Margin.
- A static orange warning appears when a margin mode is selected: "Margin trading requires
  margin to be enabled on your Binance account."
- The selected mode persists to `UserDefaults.standard` key `"selectedTradingMode"` and
  defaults to `.spot` on first launch.
- No confirmation sheet, error banner, or navigation title badge (out of scope for v1 —
  deferred to future work).

## Component Impact

- **settings** (`EasyCrypto/Features/Settings/SettingsView.swift`):
  - Added `tradingModeSection` with segmented `Picker`
  - Added `.task` modifier calling `.loadTradingMode` on appear
  - Added `.loadTradingMode` to the task chain

- **settings** (`EasyCrypto/Features/Settings/SettingsState.swift`):
  - Added `selectedTradingMode: TradingMode = .spot`

- **settings** (`EasyCrypto/Features/Settings/SettingsIntent.swift`):
  - Added `.loadTradingMode` and `.setTradingMode(TradingMode)` cases

- **settings** (`EasyCrypto/Features/Settings/SettingsProcessor.swift`):
  - Added `loadTradingMode()` — reads from UserDefaults, falls back to `.spot`
  - Added `setTradingMode(_:)` — writes raw value to UserDefaults, updates state

- **settings** (`EasyCryptoTests/Features/Settings/SettingsProcessorTests.swift`):
  - Added `SettingsTradingModeTests` suite with 6 tests

## Out of Scope

- Confirmation sheet for mode changes (deferred)
- Navigation title badge showing current mode (deferred)
- Error banner when margin API fails (deferred — handled by Portfolio/Holdings)
- Cross-device sync of mode preference

## Changes Made

### Files Modified

| File | Change |
|------|--------|
| `EasyCrypto/Features/Settings/SettingsIntent.swift` | Added `.loadTradingMode` and `.setTradingMode(TradingMode)` |
| `EasyCrypto/Features/Settings/SettingsState.swift` | Added `selectedTradingMode: TradingMode = .spot` |
| `EasyCrypto/Features/Settings/SettingsProcessor.swift` | Added `loadTradingMode()` and `setTradingMode(_:)` methods |
| `EasyCrypto/Features/Settings/SettingsView.swift` | Added `tradingModeSection` picker; added `.loadTradingMode` to `.task` |
| `EasyCryptoTests/Features/Settings/SettingsProcessorTests.swift` | Added 6 tests in `SettingsTradingModeTests` suite |

### Test Results

All 6 new tests in `SettingsTradingModeTests`:

1. `setsTradingMode` — mode updates state
2. `persistsCrossMargin` — cross-margin stored as `"cross_margin"`
3. `persistsIsolatedMargin` — isolated-margin stored as `"isolated_margin"`
4. `resetsToSpot` — switching back to spot works
5. `loadsFromUserDefaults` — reads stored isolated-margin
6. `defaultsToSpot` — missing key defaults to spot

## Evidence

- [x] tidy:preparatory
- [x] tdd:red-green
- [x] tests:unit (6 tests in SettingsTradingModeTests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-SETTINGS-003 --status passed`

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: modifies Settings files only. Spot default ensures zero behavior change
  for existing users.
- Rollback: revert commits. UserDefaults key becomes unused; processors default to spot.

## Check for Understanding

1. Why does the Picker binding use synchronous state assignment plus an async `Task`
   dispatch, instead of making the binding itself async?
2. Why is UserDefaults used instead of `@AppStorage` for persistence in this codebase?
3. How does the `TradingMode` raw value map to the UserDefaults string, and what happens
   when a stored value doesn't match any `TradingMode` case?
