---
advance:
  id: "ADV-CORE-SERVICES-002"
  title: "Loss alerts: notify when an asset's profit drops by the threshold"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "core-models", "app-shell"]
  started_at: "2026-06-26T16:17:24.000000+00:00"
  implementation_completed_at: "2026-06-26T16:22:56Z"
  review_time_estimate_minutes: 30
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

Extend the existing price-alert feature so a held asset also raises a local
notification when its unrealized profit *drops* by the configured USD amount
(default $100) — the symmetric mirror of the existing gain alert.

Reuses the existing per-coin alert toggle and `thresholdUSD` (one control governs
both directions). No new Settings UI. Builds on ADV-CORE-MODELS-001,
ADV-CORE-SERVICES-001, ADV-APP-SHELL-001, ADV-SETTINGS-001.

## Behavioral Change

After this advance, for each enabled alert:
- A **gain** notification fires when `currentProfit - lastNotifiedProfit >= thresholdUSD`
  (unchanged), advancing the gain baseline.
- A **loss** notification fires when `lastNotifiedLoss - currentProfit >= thresholdUSD`,
  advancing the loss baseline *down* to the current profit so the next loss alert
  needs a further `thresholdUSD` drop (no repeat on the same decline).
- Gain and loss baselines are tracked independently per coin and persist across launches.
- "Loses value" is measured as unrealized P&L (remaining qty × price − invested),
  consistent with the gain alert — not raw market price.

## Design Notes

- **core-models**: add `lastNotifiedLoss: Double` (default 0) to `PriceAlertConfig`.
- **core-services**: extend `PriceAlertConfigInput` with `lastNotifiedLoss`; have
  `PriceAlertService.evaluate` emit a `FiredAlert` for either direction. Add an
  `AlertDirection { gain, loss }` so the caller knows which baseline to advance;
  loss notification copy reads e.g. "BTC profit down — unrealized P&L now -X USDT".
- **app-shell**: `PriceAlertRefresher` maps `lastNotifiedLoss` into the input and,
  per fired alert, persists the advanced baseline to the matching field
  (`lastNotifiedProfit` for gain, `lastNotifiedLoss` for loss).
- Reuse the existing `UnrealizedProfit` helper unchanged.

## Planned Implementation Tasks

- [x] test (core-models): `lastNotifiedLoss` defaults to 0 and round-trips
- [x] test (core-services): loss fires when profit drops >= threshold; advances
      loss baseline down; no double-fire on the same decline; gain path unaffected;
      disabled configs never fire either direction
- [x] test (app-shell): refresher persists the correct baseline field per direction
- [x] feat (core-models): add `lastNotifiedLoss` to `PriceAlertConfig`
- [x] feat (core-services): add `AlertDirection`, extend input + `FiredAlert`,
      detect loss in `evaluate`
- [x] feat (app-shell): map loss baseline into input + persist per direction in
      `PriceAlertRefresher`

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: concurrency — same background/off-main constraints as the gain path; keep
  computation `nonisolated` and Sendable-safe.
- Risk: gain/loss baselines must advance independently and atomically to avoid
  duplicate or missed alerts.
- Risk: additive model field — new `lastNotifiedLoss` defaults to 0; existing rows
  backfill via the default (lightweight SwiftData migration, no data loss).
- Rollback: feature is additive and gated by the existing alert toggle; revert the
  advance's commits. The new model field is non-breaking if left unused.

## Evidence

- [x] tdd:red-green
- [x] tests:unit (loss cases across PriceAlertService/Config/Refresher tests; full EasyCryptoTests suite green)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-SERVICES-002 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-26 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-002.md: created advance plan

### 2026-06-26 - feat: loss alerts
- EasyCrypto/Core/Models/PriceAlertConfig.swift: add lastNotifiedLoss (default 0)
- EasyCrypto/Core/Services/PriceAlertService.swift: add AlertDirection; extend PriceAlertConfigInput + FiredAlert; evaluate fires gain and/or loss with direction-specific notification ids
- EasyCrypto/BackgroundTasks/PriceAlertRefresher.swift: map loss baseline into input; persist advanced baseline to lastNotifiedProfit/lastNotifiedLoss by direction
- EasyCryptoTests: added loss coverage (PriceAlertServiceTests +3, PriceAlertConfigTests +1, PriceAlertRefresherTests +1); updated input helper for lastNotifiedLoss
