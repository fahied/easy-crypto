---
advance:
  id: "ADV-SETTINGS-003"
  title: "Settings UI for trading mode selection — spot, cross-margin, and isolated-margin toggle"
  system: "easycrypto-core"
  primary_component: "settings"
  components: ["settings", "app-shell", "core-models", "portfolio"]
  started_at: "2026-08-07T09:00:00Z"
  implementation_completed_at: ~
  review_time_estimate_minutes: 30
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  model_usage: []
  status: planned
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

## Planned Implementation Tasks

- [ ] test: `AppStorage` default is `.spot` when no value stored
- [ ] test: mode change persists across app restarts
- [ ] test: confirmation sheet appears when switching from Spot to Margin
- [ ] test: no confirmation when switching between Cross and Isolated margin
- [ ] test: error banner appears when margin API fails
- [ ] test: navigation title updates with current mode
- [ ] tidy: add Trading Mode section to SettingsView
- [ ] tidy: add confirmation sheet for Spot ↔ Margin switches
- [ ] tidy: add error banner for margin API failures
- [ ] tidy: propagate mode change to Portfolio/Holdings/TradeHistory processors

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: modifies SettingsView and ContentView. Spot default ensures zero behavior
  change for existing users.
- Rollback: revert commits. AppStorage key becomes unused; processors default to spot.

## Evidence

- [ ] tidy:preparatory
- [ ] tdd:red-green
- [ ] tests:unit (TradingModeSettingsTests — target 5 tests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-SETTINGS-003 --status passed`

## Changes Made

*(populated during implementation)*

## Check for Understanding

1. Why is the Trading Mode selection stored in `AppStorage` rather than SwiftData,
    and what are the implications for the default value?
2. Why does switching from Spot to Margin require confirmation while switching between
    Cross and Isolated margin does not?
3. How does the selected mode propagate from Settings to the Portfolio, Holdings, and
    Trade History processors, and why is this propagation event-driven rather than
    polling?
