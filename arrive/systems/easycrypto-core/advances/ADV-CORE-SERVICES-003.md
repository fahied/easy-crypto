---
advance:
  id: "ADV-CORE-SERVICES-003"
  title: "Percent move alerts: notify when a coin's price moves ±5%"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "core-models", "app-shell", "settings"]
  started_at: "2026-06-26T16:28:56.000000+00:00"
  implementation_completed_at: "2026-06-26T16:34:33Z"
  review_time_estimate_minutes: 45
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

Add a per-coin alert that raises a local notification when the asset's USDT
**market price** moves by a configurable percentage (default 5%) up or down from a
stored reference price — independent of holdings or cost basis.

Reuses the existing per-coin alert toggle (enabling it turns on the USD gain/loss
alerts *and* this percent alert). The percent is configurable in Settings.
Builds on ADV-CORE-MODELS-001, ADV-CORE-SERVICES-001/002, ADV-APP-SHELL-001,
ADV-SETTINGS-001.

## Behavioral Change

After this advance, for each enabled alert:
- A **price-up** notification fires when `(price - referencePrice) / referencePrice * 100 >= percentThreshold`.
- A **price-down** notification fires when the change is `<= -percentThreshold`.
- On firing, `referencePrice` resets to the current price so the next percent alert
  needs a further ±`percentThreshold` move from there (no repeat on the same move).
- First-time/zero reference is initialized silently to the current price (no
  notification) so the first real alert measures from a valid baseline.
- Works even with no holdings (price-based, unlike the P&L gain/loss alerts).
- "Value" = market price, not unrealized P&L.

## Design Notes

- **core-models**: add `percentThreshold: Double = 5` and `referencePrice: Double = 0`
  to `PriceAlertConfig`.
- **core-services**: extend `AlertDirection` with `priceUp`, `priceDown`, and a
  silent `priceReference` (used to persist the initial baseline). Extend
  `PriceAlertConfigInput` with `percentThreshold` + `referencePrice`. In
  `evaluate`, after the gain/loss checks, compute the percent move from
  `referencePrice`; emit `priceReference` (no notification) when the reference is
  unset, otherwise emit `priceUp`/`priceDown` with `newBaseline = currentPrice`.
  Notification copy e.g. "BTC price up 5.2% — now 65,000 USDT".
- **app-shell**: `PriceAlertRefresher` maps the two new fields into the input and,
  per fired alert, persists `newBaseline` to `referencePrice` for the price
  directions (alongside the existing gain/loss baseline persistence).
- **settings**: extend `PriceAlertRow` + state with `percentThreshold`; add a
  `setAlertPercent(symbol:percent:)` intent + handler (upsert
  `PriceAlertConfig.percentThreshold`); add a percent field to the alert row UI.

## Planned Implementation Tasks

- [x] test (core-models): `percentThreshold` defaults to 5, `referencePrice` to 0; round-trip
- [x] test (core-services): silent reference init when unset; price-up/down fire at
      ±threshold; reference resets to current price; no double-fire on same move;
      gain/loss paths unaffected; disabled configs never fire
- [x] test (app-shell): refresher persists `referencePrice` for price directions
- [x] test (settings): `setAlertPercent` persists and updates the row
- [x] feat (core-models): add `percentThreshold` + `referencePrice`
- [x] feat (core-services): extend `AlertDirection`, input, and `evaluate` percent logic
- [x] feat (app-shell): map + persist reference price in `PriceAlertRefresher`
- [x] feat (settings): percent intent/handler/state + alert-row percent field

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: concurrency — same off-main background constraints as existing alerts.
- Risk: reference baseline must initialize silently and reset atomically to avoid
  spurious or repeated alerts.
- Risk: additive model fields default safely (`percentThreshold = 5`,
  `referencePrice = 0`); existing rows backfill via defaults (lightweight migration).
- Risk: percent alerts share the existing toggle — enabling an alert now also
  enables percent notifications; document this in the Settings copy.
- Rollback: additive and gated by the existing toggle; revert the advance's commits.
  New model fields are non-breaking if unused.

## Evidence

- [x] tdd:red-green
- [x] tests:unit (percent cases across Service/Config/Refresher/Settings tests; full EasyCryptoTests suite green)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-SERVICES-003 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-26 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-003.md: created advance plan

### 2026-06-26 - feat: percent-move alerts
- EasyCrypto/Core/Models/PriceAlertConfig.swift: add percentThreshold (default 5) + referencePrice (default 0)
- EasyCrypto/Core/Services/PriceAlertService.swift: AlertDirection += priceUp/priceDown/priceReference; input += percentThreshold/referencePrice; evaluate seeds reference silently then fires ±percent with newBaseline = price
- EasyCrypto/BackgroundTasks/PriceAlertRefresher.swift: map percent fields; persist referencePrice for price directions
- EasyCrypto/Features/Settings/*: setAlertPercent intent/handler; PriceAlertRow.percentThreshold; percent field in the alert row
- EasyCryptoTests: +5 service, +1 model, +1 refresher, +1 settings
