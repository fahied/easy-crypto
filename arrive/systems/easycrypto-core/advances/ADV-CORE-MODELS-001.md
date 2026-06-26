---
advance:
  id: "ADV-CORE-MODELS-001"
  title: "Price alert configuration & profit baseline model"
  system: "easycrypto-core"
  primary_component: "core-models"
  components: ["core-models"]
  started_at: "2026-06-26T14:30:29.000000+00:00"
  implementation_completed_at: "2026-06-26T14:38:14Z"
  review_time_estimate_minutes: 15
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: ["tdd:red-green", "tests:unit"]
  # Populated by `arrive usage import` / the LiteLLM callback — leave empty when authoring.
  model_usage: []
  status: complete
---

## Objective

Add the persisted data model that drives profit-threshold alerts: per-symbol
alert enablement, the USD threshold, and the last-notified profit baseline used to
detect a further increase. This is the foundation for ADV-CORE-SERVICES-001,
ADV-APP-SHELL-001, and ADV-SETTINGS-001.

## Behavioral Change

After this advance:
- A SwiftData model (e.g. `PriceAlertConfig`) persists per held symbol:
  `symbol`, `isEnabled`, `thresholdUSD` (default 100), `lastNotifiedProfit`.
- Configs survive app relaunch alongside existing `SyncMetadata`.
- No user-visible behavior yet — model + persistence only.

## Planned Implementation Tasks

- [x] test: model round-trips through SwiftData; defaults applied (threshold 100,
      disabled by default, baseline 0)
- [x] feat: add `PriceAlertConfig` SwiftData model in core-models
- [x] feat: register the model in the SwiftData `ModelContainer` schema

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: schema change — adding a new model to the container. Additive only; no
  migration of existing models required.
- Rollback: remove the model from the schema and delete the file; no data
  migration needed (new store table is dropped).

## Evidence

- [x] tdd:red-green
- [x] tests:unit (PriceAlertConfigTests — 5 passed)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-MODELS-001 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-26 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-CORE-MODELS-001.md: created advance plan

### 2026-06-26 - feat: add PriceAlertConfig model
- EasyCrypto/Core/Models/PriceAlertConfig.swift: new @Model (symbol unique; isEnabled, thresholdUSD=100, lastNotifiedProfit defaults)
- EasyCrypto/EasyCryptoApp.swift: registered PriceAlertConfig in ModelContainer schema
- EasyCryptoTests/Core/Models/PriceAlertConfigTests.swift: 5 tests (defaults, explicit fields, persistence, fetch-by-symbol, baseline update) — all pass
