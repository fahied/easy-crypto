---
advance:
  id: "ADV-AI-INSIGHTS-003"
  title: "AI insights pt.3: Insights MVI surface + view + settings toggle"
  system: "easycrypto-core"
  primary_component: "ai-insights"
  components: ["ai-insights", "settings"]
  started_at: "2026-06-28T00:00:00Z"
  implementation_completed_at: ~
  review_time_estimate_minutes: 30
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

**Part 3 of 4** of the on-device AI insights feature. Add the user-facing
**Insights** surface (MVI) that renders persisted `TradingInsight`s, supports a
manual refresh, communicates availability, and foregrounds the "processed on
device" privacy posture — plus a Settings toggle to enable/disable the feature.
Depends on ADV-AI-INSIGHTS-001 (models) and ADV-AI-INSIGHTS-002 (engine).

## Behavioral Change

After this advance:
- A new **Insights** screen lists persisted `TradingInsight`s (instant render from
  storage) grouped/sorted by severity and recency.
- A **manual refresh** intent runs the `FoundationModelInsightEngine` over a fresh
  `TradeSummary`, replaces persisted insights, and reflects loading/empty/error and
  availability states in the UI.
- When the model is `unavailable`, the screen shows a clear, neutral message and
  **no** silent fallback to any remote model.
- The screen surfaces a "Processed on device" affordance.
- **Settings** gains a toggle to enable/disable AI insights plus a one-line privacy
  note ("Insights are generated on your device and never leave it"). When disabled,
  the surface and (in Part 4) the scheduled refresh do not run.

## Design Notes

- **ai-insights** (`EasyCrypto/Features/Insights/**`):
  - MVI surface following `MVI.swift`: `InsightsIntent` (`load`, `refresh`),
    `InsightsState` (insights, loading, availability, error), `InsightsProcessor`
    (loads persisted insights; on refresh, summarize → engine → persist), and
    `InsightsView`.
  - Reuse design-system cards for insight rows; show availability + "on device"
    affordance.
- **settings**:
  - Add an `aiInsightsEnabled` toggle (persisted with existing settings) + privacy
    note. Gate the Insights entry point and (Part 4) the refresher on it.

## Planned Implementation Tasks

- [ ] branch: create/confirm feature branch for this advance
- [ ] test (ai-insights): `InsightsProcessor` load emits persisted insights;
      `refresh` transitions loading → loaded and persists engine output (fake engine)
- [ ] test (ai-insights): `refresh` surfaces `unavailable` state without crashing
- [ ] test (settings): `aiInsightsEnabled` toggle round-trips and gates the surface
- [ ] feat (ai-insights): `InsightsIntent`/`InsightsState`/`InsightsProcessor`
- [ ] feat (ai-insights): `InsightsView` (rows, availability, on-device affordance)
- [ ] feat (settings): enable/disable toggle + privacy note + gated entry point

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: privacy messaging — ensure the unavailable state never implies a remote
  fallback; copy must reinforce on-device processing.
- Risk: empty/first-run states — handle no-trades and no-insights gracefully.
- Rollback: surface is reachable only via the gated entry point; revert the
  advance's commits. Models/engine remain inert if the toggle is off.

## Evidence

- [ ] tdd:red-green
- [ ] tests:unit (InsightsProcessor load/refresh/unavailable, settings toggle gating)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-AI-INSIGHTS-003 --status passed` (include
    provider/run metadata when available)

## Changes Made

### 2026-06-28 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-AI-INSIGHTS-003.md: created advance plan
  (Part 3 of 4, split from the original single advance)

## Check for Understanding

1. Why does the Insights screen render from persisted `TradingInsight`s before any
   engine run, and what does the manual refresh intent do?
2. How does the UI handle the `unavailable` availability state, and why must it
   avoid implying a remote fallback?
3. What does the Settings toggle gate, and where is its value persisted?
4. Which existing architecture pattern do the Insights intent/state/processor follow?
5. How are first-run states (no trades, no insights) handled?
