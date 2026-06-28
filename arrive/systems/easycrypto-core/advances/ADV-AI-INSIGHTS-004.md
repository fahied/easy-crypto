---
advance:
  id: "ADV-AI-INSIGHTS-004"
  title: "AI insights pt.4: 4-hour background refresher + app wiring"
  system: "easycrypto-core"
  primary_component: "ai-insights"
  components: ["ai-insights", "app-shell"]
  started_at: "2026-06-28T00:00:00Z"
  implementation_completed_at: "2026-06-28T00:00:00Z"
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

**Part 4 of 4** of the on-device AI insights feature. Drive insight regeneration on
a **4-hour** cadence from the background-refresh path, reusing the throttle pattern
from ADV-CORE-SERVICES-004. Depends on ADV-AI-INSIGHTS-001 (models + summarizer),
ADV-AI-INSIGHTS-002 (engine), and ADV-AI-INSIGHTS-003 (settings toggle).

## Behavioral Change

After this advance:
- An `InsightRefresher` (sibling to `PriceAlertRefresher` / `CandleAlertRefresher`)
  runs in the background task. It reads `InsightState.lastGeneratedAt`, **skips when
  `< 4h` elapsed**, otherwise: summarizes the trade ledger → runs the engine →
  replaces persisted `TradingInsight`s → stamps `lastGeneratedAt = now`, all in one
  `@MainActor` `ModelContext` save.
- The refresher is **gated on the Settings `aiInsightsEnabled` toggle** and on model
  availability; when off/unavailable it no-ops.
- "Every 4 hours" is approximated via the persisted `lastGeneratedAt` throttle
  (iOS background wakes are best-effort), complementing the manual refresh from
  Part 3.
- New models are registered and the refresher is wired in `EasyCryptoApp`.

## Design Notes

- **app-shell**:
  - Add `EasyCrypto/BackgroundTasks/InsightRefresher.swift` mirroring
    `CandleAlertRefresher`: throttle on `InsightState.lastGeneratedAt` (≥ 4h),
    evaluate via summarizer + engine, replace insights, stamp timestamp — one save.
  - Ensure `TradingInsight` + `InsightState` are registered in the `ModelContainer`
    (if not already from Part 1) and run `InsightRefresher` from the background task
    in `EasyCryptoApp`, gated on the settings toggle.
- **ai-insights**: no new types; the refresher composes `TradePatternSummarizer` +
  `FoundationModelInsightEngine`.

## Planned Implementation Tasks

- [x] branch: create/confirm feature branch for this advance
- [x] test (app-shell): refresher skips within 4h, regenerates after, replaces
      persisted insights, and stamps `lastGeneratedAt` in one save (stub engine)
- [x] test (app-shell): refresher no-ops when the toggle is off or model unavailable
- [x] feat (app-shell): `InsightRefresher` (4h throttle + summarize + generate +
      persist)
- [x] feat (app-shell): wire refresher into the `EasyCryptoApp` background task
      (gated). Models already registered in Part 1.

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: concurrency — keep the summarizer `nonisolated`/`Sendable`, run the engine
  off the main actor, and persist insights + throttle inside one `@MainActor`
  `ModelContext` save.
- Risk: iOS cannot guarantee exact 4-hour wakes — cadence is approximated via the
  `lastGeneratedAt` throttle plus the Part 3 manual refresh; document "every 4
  hours" as best-effort.
- Risk: background cost — engine runs are bounded by the 4h throttle and the toggle;
  skip early when disabled/unavailable before doing any work.
- Rollback: refresher is additive and gated by the toggle + availability check;
  revert the advance's commits. Manual refresh (Part 3) keeps working.

## Evidence

- [x] tdd:red-green
- [x] tests:unit (refresher skip-within-4h, regenerate-after + stamp, disabled no-op,
      unavailable no-op — 4 new tests; full EasyCryptoTests suite green —
      `** TEST SUCCEEDED **`)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-AI-INSIGHTS-004 --status passed` (include
    provider/run metadata when available)

## Changes Made

### 2026-06-28 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-AI-INSIGHTS-004.md: created advance plan
  (Part 4 of 4, split from the original single advance)

### 2026-06-28 - feat: 4-hour background insight refresher
- EasyCrypto/BackgroundTasks/InsightRefresher.swift: `@MainActor` refresher — gates
  on the toggle + model availability (no work when off/unavailable), throttles on
  `InsightState.lastGeneratedAt` (≥4h), summarizes → engine → replaces `TradingInsight`s
  → stamps `lastGeneratedAt`, all in one save
- EasyCrypto/EasyCryptoApp.swift: build `TradePatternSummarizer(fifo:)` +
  `FoundationModelInsightEngine.live`; thread them through
  `registerBackgroundRefresh`/`handle`; run `InsightRefresher` after the price/candle
  refreshers in the background task
- EasyCryptoTests/Core/Services/InsightRefresherTests.swift: skip-within-4h,
  regenerate-after + stamp, disabled no-op, unavailable no-op (4 tests)

## Check for Understanding

1. How is the "every 4 hours" requirement implemented given the iOS background
   model, and what single piece of state enforces it?
2. What does the refresher do in one `ModelContext` save, and why keep it atomic?
3. What two conditions cause the refresher to no-op before doing any work?
4. How does this part relate to the manual refresh added in Part 3?
5. Which prior advance's pattern does `InsightRefresher` reuse?
