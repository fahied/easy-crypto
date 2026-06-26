---
advance:
  id: "ADV-APP-SHELL-001"
  title: "Background refresh task to run price-alert checks (~5 min)"
  system: "easycrypto-core"
  primary_component: "app-shell"
  components: ["app-shell"]
  started_at: "2026-06-26T14:30:29.000000+00:00"
  implementation_completed_at: ~
  review_time_estimate_minutes: 25
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: ["concurrency"]
  evidence: []
  # Populated by `arrive usage import` / the LiteLLM callback — leave empty when authoring.
  model_usage: []
  status: planned
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

- [ ] branch: create or confirm feature branch for this advance
- [ ] test: scheduler wiring — reschedule requested on background; expiration
      handler cancels in-flight work (testable scheduler seam)
- [ ] feat: register task identifier + handler in `EasyCryptoApp`
- [ ] feat: reschedule on `scenePhase` background; persist advanced baselines
- [ ] chore: add Info.plist keys (`BGTaskSchedulerPermittedIdentifiers`,
      `UIBackgroundModes: fetch`)

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

- [ ] tdd:red-green
- [ ] tests:unit

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-APP-SHELL-001 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-26 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-APP-SHELL-001.md: created advance plan
