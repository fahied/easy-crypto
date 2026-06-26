---
advance:
  id: "ADV-APP-SHELL-001"
  title: "Background refresh task to run price-alert checks (~5 min)"
  system: "easycrypto-core"
  primary_component: "app-shell"
  components: ["app-shell"]
  started_at: "2026-06-26T14:30:29.000000+00:00"
  implementation_completed_at: "2026-06-26T14:49:17Z"
  review_time_estimate_minutes: 25
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

Register and drive a background task that periodically invokes
`PriceAlertService` for held symbols and reschedules itself. Depends on
ADV-CORE-SERVICES-001 and ADV-CORE-MODELS-001.

iOS does not guarantee fixed background wake intervals: this uses
`BGAppRefreshTask` with an `earliestBeginDate` of ~5 minutes. The OS decides
actual cadence; "every 5 minutes" is a best-effort target, not a guarantee.

## Behavioral Change

After this advance:
- App registers a `BGAppRefreshTask` identifier at launch and reschedules it
  (~5 min) on each run and on `scenePhase` background transitions.
- On wake: load held symbols + enabled alert configs, run `PriceAlertService`,
  persist advanced baselines, and call `task.setTaskCompleted` (handling
  `expirationHandler`).
- `Info.plist` gains `BGTaskSchedulerPermittedIdentifiers` and
  `UIBackgroundModes: fetch`.

## Planned Implementation Tasks

- [x] test: data flow — `PriceAlertRefresher.run` loads enabled configs + trades,
      evaluates, and persists advanced baselines (in-memory SwiftData). BGTask
      scheduler glue itself is thin/integration-only (`BGAppRefreshTask` cannot be
      unit-constructed), so the testable seam is the refresher
- [x] feat: register task identifier + handler in `EasyCryptoApp`
- [x] feat: reschedule on `scenePhase` background; persist advanced baselines
- [x] chore: add Info.plist keys (`BGTaskSchedulerPermittedIdentifiers`,
      `UIBackgroundModes: fetch`) via partial Info.plist merged with INFOPLIST_FILE

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: iOS throttles/coalesces background refresh — alerts may be delayed.
  Documented OS constraint, not a bug.
- Risk: concurrency — bridge background task to `nonisolated` services and
  marshal SwiftData writes on the correct actor; always complete the task.
- Rollback: remove task registration + Info.plist keys; services/model remain
  inert. No data migration.

## Evidence

- [x] tdd:red-green
- [x] tests:unit (PriceAlertRefresherTests 3 — all pass; full EasyCryptoTests suite green)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-APP-SHELL-001 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-26 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-APP-SHELL-001.md: created advance plan

### 2026-06-26 - feat: background refresh wiring
- EasyCrypto/BackgroundTasks/PriceAlertRefresher.swift: testable runner (configs+trades → evaluate → persist baselines)
- EasyCrypto/EasyCryptoApp.swift: register BGAppRefreshTask, scheduleAppRefresh (~5 min), handle with expirationHandler, reschedule on scenePhase .background; construct NotificationService + PriceAlertService
- EasyCrypto/Info.plist: BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes(fetch)
- EasyCrypto.xcodeproj/project.pbxproj: INFOPLIST_FILE for app configs; Info.plist excluded from resources via synchronized-group membershipExceptions
- arrive/.../components/app-shell.yaml: selectors include BackgroundTasks/** and Info.plist
- EasyCryptoTests/Core/Services/PriceAlertRefresherTests.swift: 3 tests — verified merged Info.plist (background arrays + scene manifest coexist)
