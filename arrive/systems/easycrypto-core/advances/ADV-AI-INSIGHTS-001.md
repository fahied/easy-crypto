---
advance:
  id: "ADV-AI-INSIGHTS-001"
  title: "AI insights pt.1: persistence models + deterministic trade-pattern summarizer"
  system: "easycrypto-core"
  primary_component: "ai-insights"
  components: ["ai-insights", "core-models"]
  started_at: "2026-06-28T00:00:00Z"
  implementation_completed_at: "2026-06-28T00:00:00Z"
  review_time_estimate_minutes: 25
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

**Part 1 of 4** of the on-device AI insights feature (see ADV-AI-INSIGHTS-002/003/004).
Lay the deterministic, AI-free foundation: the persistence models that store
generated insights and the pure `TradePatternSummarizer` that reduces the local
trade ledger into a compact statistical summary. No Foundation Models dependency
is introduced here — everything in this advance is plain Swift and fully unit
testable. Builds on the existing trade import and FIFO P&L work
(ADV-CORE-MODELS-001, ADV-CORE-SERVICES-001/002/003).

## Behavioral Change

After this advance:
- Two new SwiftData entities exist and are registered in the `ModelContainer`:
  - `TradingInsight` — a persisted insight (title, body, category, severity,
    `generatedAt`, optional `symbol`).
  - `InsightState` — a single-row entity holding `lastGeneratedAt: Date` (the
    4-hour throttle anchor consumed in Part 4), same pattern as `CandleAlertState`.
- A deterministic `TradePatternSummarizer` maps `[Trade]` → a bounded
  `TradeSummary` value: per-symbol counts, realized P&L (via the existing FIFO
  calculator), win/loss ratio, average holding period, recent win/loss streaks, and
  concentration. The summary is **bounded in size regardless of ledger length** so
  later parts can feed it to the on-device model context.
- No UI, no AI, and no background work yet — this part only adds storage + the
  summary transform.

## Why this split

The summary is the privacy boundary for the whole feature: the model in Part 2
only ever sees `TradeSummary`, never raw trades. Landing it first — pure and
exhaustively tested — lets every later part build on a verified, deterministic
input without entangling the Foundation Models dependency.

## Design Notes

- **core-models**:
  - Add `TradingInsight` `@Model` (title, body, category, severity, `generatedAt`,
    optional `symbol`). Register in the schema.
  - Add single-row `InsightState` `@Model` (`lastGeneratedAt: Date`), mirroring
    `CandleAlertState`. Register in the schema.
- **ai-insights** (new component, `EasyCrypto/Core/AI/**`):
  - Add a bounded `TradeSummary` value type (`Sendable`) and a pure
    `TradePatternSummarizer` mapping `[Trade]` → `TradeSummary`. Reuse the existing
    FIFO calculator for realized P&L. No AI, no I/O — deterministic and `Sendable`.

## Planned Implementation Tasks

- [x] branch: create/confirm feature branch for this advance
- [x] test (core-models): `TradingInsight` + `InsightState` round-trip in SwiftData
- [x] test (ai-insights): `TradePatternSummarizer` produces correct per-symbol
      aggregates, realized P&L, win/loss, hold time, and streaks for fixture trades
- [x] test (ai-insights): summary stays bounded (fixed shape) regardless of ledger
      size
- [x] feat (core-models): add `TradingInsight` + `InsightState`; register schema
- [x] feat (ai-insights): `TradeSummary` + `TradePatternSummarizer`

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: additive model changes — new `TradingInsight` + `InsightState` entities are
  non-breaking (lightweight SwiftData migration).
- Risk: summary fidelity — realized P&L must reuse the existing FIFO calculator so
  insights stay consistent with the rest of the app; covered by unit tests against
  fixture trades.
- Rollback: feature is additive and unused by any surface until Part 3/4; revert the
  advance's commits. New entities are inert if unused.

## Evidence

- [x] tdd:red-green
- [x] tests:unit (TradingInsight/InsightState round-trip, TradePatternSummarizer
      aggregates + boundedness — 6 new tests; full EasyCryptoTests suite green —
      `** TEST SUCCEEDED **`)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-AI-INSIGHTS-001 --status passed` (include
    provider/run metadata when available)

## Changes Made

### 2026-06-28 - docs: draft advance
- arrive/systems/easycrypto-core/components/ai-insights.yaml: new component for the
  on-device AI insights surface (Apple Foundation Models)
- arrive/systems/easycrypto-core/advances/ADV-AI-INSIGHTS-001.md: created advance plan
  (split from the original single advance into Part 1 of 4)

### 2026-06-28 - feat: persistence models + deterministic summarizer
- EasyCrypto/Core/Models/TradingInsight.swift: new `@Model` (title, body, category,
  severity, optional symbol, generatedAt) persisting generated insights
- EasyCrypto/Core/Models/InsightState.swift: new single-row `@Model`
  (`lastGeneratedAt`) for the 4-hour throttle (mirrors `CandleAlertState`)
- EasyCrypto/Core/AI/TradeSummary.swift: bounded `Sendable` `TradeSummary` +
  `SymbolSummary` (the privacy boundary; `topSymbols` capped at `maxSymbols`)
- EasyCrypto/Core/AI/TradePatternSummarizer.swift: pure `nonisolated` summarizer
  mapping `[Trade]` → `TradeSummary` (per-symbol aggregates, realized P&L via the
  injected `FIFOCalculator`, win/loss sells, trailing win/loss streaks, average
  holding span, concentration)
- EasyCrypto/EasyCryptoApp.swift: register `TradingInsight.self` + `InsightState.self`
  in the `ModelContainer` schema
- EasyCryptoTests/Core/Models/TradingInsightTests.swift: model round-trip (2 tests)
- EasyCryptoTests/Core/AI/TradePatternSummarizerTests.swift: summarizer aggregates,
  streaks, empty ledger, boundedness (4 tests)

## Check for Understanding

1. Why is the deterministic `TradePatternSummarizer` landed first, before any
   Foundation Models code, and how does it act as the privacy boundary for the
   whole feature?
2. What two SwiftData entities does this part add, and what is each responsible for?
3. Why must `TradeSummary` be bounded in size regardless of how many trades exist?
4. Why does the summarizer reuse the existing FIFO calculator rather than computing
   realized P&L independently?
5. What does `InsightState.lastGeneratedAt` exist for, given nothing reads it until
   Part 4?
