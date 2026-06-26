---
advance:
  id: "ADV-SETTINGS-001"
  title: "Settings UI for price alerts (permission, per-asset toggle, threshold)"
  system: "easycrypto-core"
  primary_component: "settings"
  components: ["settings"]
  started_at: "2026-06-26T14:30:29.000000+00:00"
  implementation_completed_at: ~
  review_time_estimate_minutes: 25
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  # Populated by `arrive usage import` / the LiteLLM callback — leave empty when authoring.
  model_usage: []
  status: planned
---

## Objective

Let users control price alerts from Settings: request notification permission,
toggle alerts per held asset, and set the USD threshold (default $100). Depends on
ADV-CORE-SERVICES-001 (NotificationService) and ADV-CORE-MODELS-001 (config model).

## Behavioral Change

After this advance:
- Settings shows a notification-permission prompt and reflects denied/authorized state.
- Per held asset: an enable toggle and an editable USD threshold (default 100),
  persisted via `PriceAlertConfig`.
- Changes flow through the Settings MVI processor (intent → processor → state → view).
- Alerts default off until the user enables and grants permission.

## Planned Implementation Tasks

- [ ] branch: create or confirm feature branch for this advance
- [ ] test: processor intents — request permission, toggle alert, edit threshold
      update state and persist config
- [ ] feat: add alert intents to `SettingsIntent` + handlers in `SettingsProcessor`
- [ ] feat: extend `SettingsState` with permission status + per-asset alert rows
- [ ] feat: build the alerts section in `SettingsView`

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: permission denial silently disables alerts — surface denied state and a
  link to system Settings.
- Rollback: remove the alerts section + intents; model/services remain inert.

## Evidence

- [ ] tdd:red-green
- [ ] tests:unit

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-SETTINGS-001 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-26 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-SETTINGS-001.md: created advance plan
