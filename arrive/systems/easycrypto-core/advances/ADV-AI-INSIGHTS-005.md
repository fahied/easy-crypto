---
advance:
  id: "ADV-AI-INSIGHTS-005"
  title: "AI insights pt.5: conversational chat with the on-device model in Insights"
  system: "easycrypto-core"
  primary_component: "ai-insights"
  components: ["ai-insights"]
  started_at: "2026-06-28T00:00:00Z"
  implementation_completed_at: "2026-06-29T00:00:00Z"
  review_time_estimate_minutes: 45
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: ["new_dependency", "concurrency"]
  evidence: ["tdd:red-green", "tests:unit"]
  # Populated by `arrive usage import` / the LiteLLM callback — leave empty when authoring.
  model_usage: []
  status: complete
---

## Objective

Add a **conversational chat** to the Insights surface so the user can ask
follow-up questions about their trading and get answers from the **on-device**
Apple Foundation Models model — multi-turn, grounded in the same bounded
`TradeSummary` that powers the generated insights (ADV-AI-INSIGHTS-001/002). The
chat runs **entirely on device**: no network in the chat path and no remote/cloud
model. Reuses the availability gating and the Settings `aiInsightsEnabled` toggle
from ADV-AI-INSIGHTS-002/003.

## Behavioral Change

After this advance:
- The **Insights** tab gains a chat affordance (e.g. an "Ask" entry that presents a
  chat sheet). The user types questions like "Why is my BTC position risky?" or
  "How can I improve my win rate?" and receives plain-language answers.
- Answers come from a **persistent** on-device `LanguageModelSession` that keeps
  multi-turn context across messages (the session transcript), so follow-ups work
  naturally without re-sending history.
- The conversation is **grounded** by seeding the session's instructions with the
  bounded `TradeSummary` (the same privacy boundary as the rest of the feature) —
  the model can discuss the user's trading using aggregates only, **never** raw
  trades.
- Responses **stream** token-by-token into the UI where supported, with a typing
  indicator; a non-streaming fallback is acceptable.
- The chat is gated on the Settings toggle and on `SystemLanguageModel.default`
  availability: when off/unavailable it shows a clear, neutral message and **no**
  remote fallback.
- The transcript is **in-memory for the session** (not persisted) in this advance;
  closing the chat clears it. Persisting chat history is out of scope (see
  Out of Scope).

## On-Device-Only Constraint (non-negotiable)

- Uses **only** `import FoundationModels` / `SystemLanguageModel.default`.
- The chat path performs **no** `URLSession`/network I/O and seeds the session with
  only the bounded `TradeSummary` (never raw trades).
- No prompt, message, or summary is logged off-device or sent to analytics.

## Design Notes

- **ai-insights** (`EasyCrypto/Core/AI/**` + `EasyCrypto/Features/Insights/**`):
  - `InsightChatMessage` — `Sendable`, `Identifiable` value: `role` (`.user` /
    `.assistant`), `text`, `timestamp`.
  - `InsightChatResponder` protocol seam — a **stateful**, multi-turn responder:
    `func reply(to message: String) -> AsyncThrowingStream<String, Error>` (or
    `func reply(to:) async throws -> String` for the non-streaming variant). Tests
    inject a fake; no real LLM call in tests.
  - `LanguageModelChatResponder` (live adapter) — holds one persistent
    `LanguageModelSession(instructions:)` seeded from `InsightChatPrompt`
    (instructions + `TradeSummary` context), and calls `respond(to:)` /
    `streamResponse(to:)` per user turn so the session transcript carries context.
  - `InsightChatPrompt` — builds the grounding instructions from a `TradeSummary`
    (reuse `InsightPrompt` helpers), constraining the assistant to the supplied
    aggregates and to concise, on-topic, non-advice-disclaimed answers.
  - MVI surface following `MVI.swift`: `InsightChatIntent` (`sendMessage(String)`,
    `clear`), `InsightChatState` (messages, isResponding, availability, error,
    inputText), `InsightChatProcessor` (builds the summary once, owns the responder,
    appends the user message, streams/awaits the reply, updates state), and a
    `InsightChatView` (message list, streaming bubble, input bar, availability/empty
    states, "processed on device" footer) presented from `InsightsView`.
  - Gate on `InsightSettingsStore.isEnabled()` and engine/model availability
    (reuse `FoundationModelInsightEngine.Availability` or the same
    `SystemLanguageModel.default.availability` mapping).

## Out of Scope (this advance)

- Persisting chat history across launches (kept in-memory per session).
- Tools / function-calling, retrieval over raw trades, or multi-session management.
- Changing the generated-insights flow (Parts 1–4) — chat is additive.

## Planned Implementation Tasks

- [x] branch: create/confirm feature branch for this advance
- [x] test (ai-insights): `InsightChatProcessor.sendMessage` appends the user message,
      invokes the responder, appends the assistant reply, and toggles `isResponding`
      (fake responder)
- [x] test (ai-insights): streaming responder yields cumulative snapshots; the final
      assistant message holds the full text
- [x] test (ai-insights): when disabled or model unavailable, `sendMessage` is
      blocked with a clear state and no responder call
- [x] test (ai-insights): the responder is seeded with the bounded `TradeSummary`
      only (fake captures the summary; raw trades never appear)
- [x] test (ai-insights): a reply failure drops the empty placeholder and sets `error`;
      `clear` resets the conversation
- [x] feat (ai-insights): `InsightChatMessage`, `InsightChatResponder` seam +
      `LanguageModelChatResponder` (persistent session, streaming) + `InsightChatPrompt`
- [x] feat (ai-insights): `InsightChatIntent`/`InsightChatState`/`InsightChatProcessor`
- [x] feat (ai-insights): `InsightChatView` + entry point (Ask button + sheet) from
      `InsightsView`; wired in `ContentView`

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: new_dependency — deepens use of `FoundationModels` (persistent session +
  streaming); guard behind `SystemLanguageModel.default.availability` so unsupported
  devices degrade gracefully.
- Risk: privacy — keep the chat path free of network I/O and seed the session with
  only the bounded `TradeSummary` (never raw trades); never log messages/summaries
  off device. The model must not be given raw trade rows even via follow-ups.
- Risk: concurrency — the persistent `LanguageModelSession` is held by an
  `@Observable` `@MainActor` processor; stream updates must marshal back to the main
  actor; guard against overlapping `sendMessage` calls (disable input while
  responding) since a session cannot service concurrent requests.
- Risk: context growth — long chats grow the session transcript toward the on-device
  context limit; seed a compact summary, keep answers concise, and surface a graceful
  error (offer "clear") if the model reports context exhaustion.
- Risk: latency / partial output — stream tokens with a typing indicator; handle
  cancellation when the sheet is dismissed mid-response.
- Rollback: feature is additive and gated by the toggle + availability; revert the
  advance's commits. The generated-insights flow is untouched.

## Evidence

- [x] tdd:red-green
- [x] tests:unit (chat turn-taking + cumulative streaming, summary-only grounding,
      disabled/unavailable gating, failure-drops-placeholder, clear — 6 new tests;
      full EasyCryptoTests suite green — `** TEST SUCCEEDED **`)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-AI-INSIGHTS-005 --status passed` (include
    provider/run metadata when available)

## Changes Made

### 2026-06-28 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-AI-INSIGHTS-005.md: created advance plan
  (conversational on-device chat in Insights)

### 2026-06-29 - feat: on-device conversational chat
- EasyCrypto/Core/AI/InsightChat.swift: `InsightChatMessage`; `InsightChatResponder`
  seam; `LanguageModelChatResponder` (persistent `LanguageModelSession` +
  `streamResponse` yielding cumulative text); `InsightChatPrompt` (summary-grounded
  instructions, reuses `InsightPrompt`)
- EasyCrypto/Features/Insights/InsightChatState.swift: messages, inputText,
  isResponding, availability, error
- EasyCrypto/Features/Insights/InsightChatIntent.swift: start / sendMessage / clear
- EasyCrypto/Features/Insights/InsightChatProcessor.swift: gates on toggle +
  availability, lazily builds the grounded responder, streams cumulative replies,
  blocks overlapping turns, drops empty placeholder on failure
- EasyCrypto/Features/Insights/InsightChatView.swift: chat bubbles, typing indicator,
  input bar, availability/empty states, on-device note, clear button, preview
- EasyCrypto/Features/Insights/InsightsView.swift: "Ask a question" button + chat sheet
  (new `makeChatProcessor` factory param)
- EasyCrypto/ContentView.swift: supply `makeChatProcessor` to the Insights tab
- EasyCryptoTests/Features/Insights/InsightChatProcessorTests.swift: 6 tests

## Check for Understanding

1. How does the chat keep multi-turn context across messages, and why is a single
   persistent `LanguageModelSession` used rather than one session per message?
2. What grounds the assistant's answers, and how does this advance keep the privacy
   guarantee that raw trades never reach the model — even on follow-up questions?
3. Why must the UI disable input while a response is in flight, and how do streaming
   updates marshal back to the main actor?
4. What happens when the feature is disabled or Apple Intelligence is unavailable,
   and where is that decision made?
5. Why is chat history kept in-memory for the session in this advance, and what is
   explicitly out of scope?
