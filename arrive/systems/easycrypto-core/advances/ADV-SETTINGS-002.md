---
advance:
  id: "ADV-SETTINGS-002"
  title: "Notification log: persist fired alerts and browse them from Settings"
  system: "easycrypto-core"
  primary_component: "settings"
  components: ["settings", "core-models", "core-services", "app-shell"]
  started_at: "2026-06-27T00:00:00Z"
  implementation_completed_at: "2026-06-27T00:00:00Z"
  review_time_estimate_minutes: 40
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: ["concurrency"]
  evidence: ["tdd:red-green", "tests:unit"]
  # Populated by `arrive usage import` / the LiteLLM callback — leave empty when authoring.
  model_usage: []
  status: complete
---

## Objective

Keep a persistent log of every local notification the app fires (gain, loss,
price-up, price-down) and expose it in Settings as a "Notification Log" menu item.
Tapping the item lists fired notifications newest-first; tapping a row opens a
detail view with the full notification copy and context. Builds on
ADV-CORE-MODELS-001, ADV-CORE-SERVICES-001/002/003, ADV-APP-SHELL-001, ADV-SETTINGS-001.

## Behavioral Change

After this advance:
- Each time a price alert fires and a notification is delivered, a record is saved
  with the exact title/body the user saw, plus symbol, asset, direction, value, and
  the time it fired.
- Settings shows a **Notification Log** menu item; tapping it presents the list of
  fired notifications, most recent first (empty-state copy when none yet).
- Tapping a log row opens a detail view showing the full notification title, body,
  symbol/asset, direction, value, and timestamp.
- Silent reference-price seeding (`AlertDirection.priceReference`) is *not* logged —
  only entries that actually delivered a notification appear.
- Log entries persist across launches via SwiftData and survive app restarts.

## Design Notes

- **core-models**: add a `NotificationLogEntry` `@Model` (`id: UUID`, `symbol`,
  `asset`, `title`, `body`, `direction: String`, `value: Double`, `firedAt: Date`).
  Register it in the app's `ModelContainer` schema.
- **core-services**: extend `FiredAlert` with `deliveredAlert: LocalAlert?` so the
  exact delivered copy is available to the caller. `PriceAlertService.evaluate`
  populates it with the `LocalAlert` it scheduled for gain/loss/priceUp/priceDown,
  and leaves it `nil` for the silent `.priceReference` direction (no behavior change
  to firing logic — additive field only).
- **app-shell**: in `PriceAlertRefresher.run`, after persisting baselines, insert a
  `NotificationLogEntry` for each fired alert whose `deliveredAlert != nil`
  (capturing title/body/symbol/asset/direction/value/`firedAt`) and save in the same
  `ModelContext` transaction. Add `NotificationLogEntry.self` to the
  `ModelContainer` schema in `EasyCryptoApp`.
- **settings**: add a `loadNotificationLog` intent + handler that fetches entries
  sorted by `firedAt` descending into a new `[NotificationLogRow]` on
  `SettingsState`; add a Notification Log section/menu item in `SettingsView` that
  navigates to a `NotificationLogView` (list) and a `NotificationLogDetailView`
  (per-entry detail).

## Planned Implementation Tasks

- [x] test (core-models): `NotificationLogEntry` initializes and round-trips through
      an in-memory `ModelContainer`
- [x] test (core-services): `evaluate` populates `deliveredAlert` for fired
      gain/loss/percent alerts and leaves it `nil` for `.priceReference`
- [x] test (app-shell): `PriceAlertRefresher.run` writes one `NotificationLogEntry`
      per delivered alert (and none for silent reference seeding)
- [x] test (settings): `loadNotificationLog` populates `notificationLog` rows sorted
      newest-first
- [x] feat (core-models): add `NotificationLogEntry`
- [x] feat (core-services): add `deliveredAlert` to `FiredAlert`; set it in `evaluate`
- [x] feat (app-shell): persist log entries in the refresher; register the model
- [x] feat (settings): intent + handler + state + Notification Log list/detail UI

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: concurrency — log writes happen on the `@MainActor` `ModelContext` in the
  background-refresh path; keep inserts inside the existing save transaction so a
  failure rolls back baselines and log together (no partial state).
- Risk: unbounded growth — the log grows with every fired alert; acceptable for now,
  but note a future cap/retention policy if volume becomes a concern.
- Risk: additive model + schema change — new `NotificationLogEntry` is a new entity
  (lightweight SwiftData migration, no existing data touched); `deliveredAlert` is an
  optional additive field defaulting to `nil`.
- Rollback: feature is additive and read-only for users; revert the advance's
  commits. Removing the Settings section leaves the model/services inert; the new
  entity is non-breaking if left unused.

## Evidence

- [x] tdd:red-green
- [x] tests:unit (NotificationLogEntry, PriceAlertService deliveredAlert,
      PriceAlertRefresher logging, Settings notification-log loading; full
      EasyCryptoTests suite green — `** TEST SUCCEEDED **`)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-SETTINGS-002 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-27 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-SETTINGS-002.md: created advance plan

### 2026-06-27 - feat: notification log
- EasyCrypto/Core/Models/NotificationLogEntry.swift: new `@Model` (id, symbol, asset, title, body, direction, value, firedAt)
- EasyCrypto/Core/Services/PriceAlertService.swift: add `deliveredAlert: LocalAlert?` to `FiredAlert`; populate it for fired gain/loss/priceUp/priceDown and leave nil for `.priceReference`
- EasyCrypto/BackgroundTasks/PriceAlertRefresher.swift: insert a `NotificationLogEntry` per delivered alert inside the existing save transaction; add `directionLabel` mapping
- EasyCrypto/EasyCryptoApp.swift: register `NotificationLogEntry.self` in the `ModelContainer` schema
- EasyCrypto/Features/Settings/SettingsIntent.swift: add `loadNotificationLog`
- EasyCrypto/Features/Settings/SettingsState.swift: add `NotificationLogRow` + `notificationLog`
- EasyCrypto/Features/Settings/SettingsProcessor.swift: `loadNotificationLog` handler (fetch sorted by `firedAt` desc → rows)
- EasyCrypto/Features/Settings/SettingsView.swift: add Notification Log menu item navigating to the log
- EasyCrypto/Features/Settings/NotificationLogView.swift: new list + detail views
- EasyCryptoTests: NotificationLogEntryTests (1); PriceAlertServiceTests (+2 deliveredAlert); PriceAlertRefresherTests (+2 logging); SettingsAlertsProcessorTests (+1 loadNotificationLog); registered the model in the three SwiftData test containers

## Check for Understanding

1. Why is logging done in `PriceAlertRefresher.run` rather than inside
   `NotificationService.scheduleAlert`, and what does that imply about which code
   path delivers notifications today?
2. Why does the design add `deliveredAlert: LocalAlert?` to `FiredAlert` instead of
   reconstructing the notification copy in the refresher when writing the log?
3. Why are `AlertDirection.priceReference` outcomes intentionally excluded from the
   notification log?
4. How does keeping the `NotificationLogEntry` insert inside the same `ModelContext`
   save transaction as the baseline updates protect against partial/inconsistent
   state if the save fails?
5. Which components must change for a fired alert to appear in the Settings
   Notification Log, and what is each one responsible for?
