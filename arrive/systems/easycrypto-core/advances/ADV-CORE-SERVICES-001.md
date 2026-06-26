---
advance:
  id: "ADV-CORE-SERVICES-001"
  title: "Notification & price-alert services (profit-threshold detection)"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services"]
  started_at: "2026-06-26T14:30:29.000000+00:00"
  implementation_completed_at: ~
  review_time_estimate_minutes: 30
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

Add the service-layer logic that, given held symbols and their alert configs,
fetches current prices, recomputes unrealized profit via FIFO, decides which
profit-threshold alerts to fire, and delivers local notifications. Depends on
ADV-CORE-MODELS-001 (alert config + baseline).

## Behavioral Change

After this advance:
- New `NotificationService` (swift-dependencies client, `nonisolated`):
  request authorization, schedule/clear local notifications.
- New `PriceAlertService` (swift-dependencies client, `nonisolated`): for each
  enabled alert, fetch price via `PriceService`, compute profit via
  `FIFOCalculator`, and fire when `currentProfit - lastNotifiedProfit >= thresholdUSD`.
- After firing, the returned/updated baseline advances so the next alert needs a
  further +threshold gain (no repeat on the same increase).
- Pure logic + notification delivery; not yet wired to a background trigger or UI.

## Design Notes

- Both clients expose `liveValue`, `previewValue`, and `testValue`.
- Keep computation `nonisolated`; the service returns updated baselines rather than
  writing SwiftData itself, so callers control persistence/actor isolation.

## Planned Implementation Tasks

- [ ] branch: create or confirm feature branch for this advance
- [ ] tidy: extract per-asset unrealized-profit computation into a shared helper
      reused by foreground and alert paths
- [ ] test: `PriceAlertService` fires only when increase >= threshold; skips
      disabled alerts; advances baseline; no double-fire on the same gain
- [ ] test: `NotificationService` authorization + schedule behavior (via test client)
- [ ] feat: add `NotificationService` client (live/preview/test)
- [ ] feat: add `PriceAlertService` client (live/preview/test)

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: concurrency — runs off the main actor; keep polling/computation
  `nonisolated` and Sendable-safe.
- Risk: duplicate notifications if the baseline isn't advanced atomically by the caller.
- Rollback: additive new files; revert commits to remove. No callers ship until
  ADV-APP-SHELL-001 / ADV-SETTINGS-001 wire them in.

## Evidence

- [ ] tidy:preparatory
- [ ] tdd:red-green
- [ ] tests:unit

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-SERVICES-001 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-26 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-001.md: created advance plan
