---
advance:
  id: "ADV-CORE-SERVICES-004"
  title: "Hourly candle-drop alert: notify on 2 consecutive falling 15m candles"
  system: "easycrypto-core"
  primary_component: "core-services"
  components: ["core-services", "core-models", "app-shell", "settings"]
  started_at: "2026-06-27T00:00:00Z"
  implementation_completed_at: "2026-06-27T00:00:00Z"
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

Add an hourly per-coin alert that inspects the most recent 15-minute candles and
raises a local notification when the asset's price is falling — specifically when
the **last two closed 15m candles each closed lower than the candle before them**
(two consecutive lower closes). Reuses the existing per-coin alert toggle and feeds
the notification log from ADV-SETTINGS-002. Builds on ADV-CORE-MODELS-001,
ADV-CORE-SERVICES-001/002/003, ADV-APP-SHELL-001, ADV-SETTINGS-001/002.

## Behavioral Change

After this advance, for each enabled alert, at most once per hour:
- The app fetches the last **4 closed 15m candles** for the symbol.
- A **candle-drop** notification fires when the two most recent candle-to-candle
  moves are both negative — i.e. `c3.close < c2.close` **and** `c4.close < c3.close`
  for the last four closed candles `c1…c4` (the 4th is the most recent closed
  candle; `c1` is contextual buffer).
- The in-progress (still-forming) candle is ignored; only closed candles count.
- Each fired candle-drop is recorded in the Settings **Notification Log**
  (direction `candleDrop`) alongside the existing alerts.
- De-duplication: the alert fires at most once per candle — re-checks within the
  same latest candle do not re-notify.
- Hourly cadence: the candle check runs at most once every 60 minutes. iOS
  background wakes are best-effort, so "hourly" is approximated by throttling on a
  persisted last-checked timestamp rather than a guaranteed wall-clock hour.

## Design Decision — what counts as a "drop"

"Last 2 candles consecutively show a drop" is implemented as **two consecutive
lower closes** (`close[n] < close[n-1]`), measuring the downward trend across the
last two candle boundaries. The alternative reading — two consecutive **bearish**
candles (`close < open` within each candle) — was not chosen. If the bearish-candle
reading is preferred, only the predicate in `CandleDrop.isConsecutiveDrop` changes;
the rest of the design is unaffected.

## Design Notes

- **core-models**:
  - Add `lastCandleDropOpenTime: Int64 = 0` to `PriceAlertConfig` — the `openTime`
    of the latest candle that triggered a drop alert, used for per-coin de-dup.
  - Add a single-row `CandleAlertState` `@Model` with `lastCheckedAt: Date` for the
    global hourly throttle. Register both in the `ModelContainer` schema.
- **core-services**:
  - Add `AlertDirection.candleDrop`.
  - Add a pure helper `CandleDrop.isConsecutiveDrop(_ closed: [Kline]) -> Bool`
    encapsulating the two-consecutive-lower-closes rule (easy to unit test, easy to
    swap for the bearish-candle reading).
  - Add a `CandleAlertService` (struct-with-closures) whose `evaluate` takes the
    enabled configs plus a kline fetcher, fetches the last 4 closed 15m candles per
    symbol, applies `isConsecutiveDrop`, and — when the latest candle `openTime`
    differs from `lastCandleDropOpenTime` — delivers a `LocalAlert` and returns a
    `FiredAlert` (`direction: .candleDrop`, `newBaseline = Double(latestOpenTime)`,
    `deliveredAlert` set). Notification copy e.g.
    "BTC dropping — 2 consecutive 15m candles down (now X USDT)".
- **app-shell**:
  - Extend the background path (a `CandleAlertRefresher`, sibling to
    `PriceAlertRefresher`) to: read `CandleAlertState.lastCheckedAt` and skip when
    `< 60 min` elapsed; otherwise evaluate candle drops, persist
    `lastCandleDropOpenTime` per fired config, write a `NotificationLogEntry` per
    delivered alert (reusing ADV-SETTINGS-002), and stamp `lastCheckedAt = now` —
    all in one `ModelContext` save. Inject `BinanceAPIClient.fetchKlines` (interval
    `"15m"`, limit large enough to yield 4 closed candles after dropping the
    in-progress one). Register the new model and wire the refresher in
    `EasyCryptoApp`.
- **settings**: extend the notification-log formatting (`NotificationLogView`) with
  an icon/label for the `candleDrop` direction.

## Planned Implementation Tasks

- [x] test (core-services): `CandleDrop.isConsecutiveDrop` true for two consecutive
      lower closes; false for flat/recovering/single-drop sequences
- [x] test (core-services): `CandleAlertService.evaluate` fires `.candleDrop` once,
      sets `deliveredAlert`, and de-dups on the same latest `openTime`
- [x] test (core-models): `CandleAlertState` and `lastCandleDropOpenTime` round-trip
- [x] test (app-shell): refresher skips within 60 min, evaluates after, persists
      de-dup + throttle, and writes a notification-log entry per delivered alert
- [x] feat (core-models): add `lastCandleDropOpenTime` + `CandleAlertState`
- [x] feat (core-services): add `.candleDrop`, `CandleDrop.isConsecutiveDrop`,
      `CandleAlertService`
- [x] feat (app-shell): `CandleAlertRefresher` (throttle + evaluate + persist + log);
      register model; wire in `EasyCryptoApp`
- [x] feat (settings): notification-log icon/label for `candleDrop`

## Bug Fixes

- [ ] None yet

## Risk + Rollback

- Risk: concurrency — candle evaluation runs on the `@MainActor` `ModelContext` in
  the background-refresh path; keep the kline computation `nonisolated`/Sendable and
  persist de-dup, throttle, and log inside one save transaction.
- Risk: extra network load — fetching klines per enabled symbol each hour; bounded
  by the once-per-hour throttle and the enabled-coin set.
- Risk: iOS cannot guarantee exact hourly wakes — cadence is approximated via the
  `lastCheckedAt` throttle; document this so "hourly" is understood as best-effort.
- Risk: interpretation of "drop" (see Design Decision) — isolated in one predicate
  so it can be changed without touching the rest of the flow.
- Risk: additive model changes — new `lastCandleDropOpenTime` (default 0) and the
  new `CandleAlertState` entity are non-breaking (lightweight SwiftData migration).
- Rollback: feature is additive and gated by the existing per-coin alert toggle;
  revert the advance's commits. New fields/entity are inert if unused.

## Evidence

- [x] tdd:red-green
- [x] tests:unit (CandleDrop predicate, CandleAlertService, CandleAlertState model,
      CandleAlertRefresher throttle/persist/log — 16 new tests; full EasyCryptoTests
      suite green — `** TEST SUCCEEDED **`)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-CORE-SERVICES-004 --status passed` (include provider/run metadata when available)

## Changes Made

### 2026-06-27 - docs: draft advance
- arrive/systems/easycrypto-core/advances/ADV-CORE-SERVICES-004.md: created advance plan

### 2026-06-27 - feat: hourly candle-drop alert
- EasyCrypto/Core/Models/CandleAlertState.swift: new single-row `@Model` (`lastCheckedAt`) for the hourly throttle
- EasyCrypto/Core/Models/PriceAlertConfig.swift: add `lastCandleDropOpenTime: Int64 = 0` (per-coin de-dup)
- EasyCrypto/Core/Services/PriceAlertService.swift: add `AlertDirection.candleDrop`
- EasyCrypto/Core/Services/CandleAlertService.swift: new `CandleDrop.isConsecutiveDrop` rule + `CandleAlertService` (fetch last 4 closed 15m candles, fire on two consecutive lower closes, de-dup by latest `openTime`)
- EasyCrypto/BackgroundTasks/PriceAlertRefresher.swift: handle new `.candleDrop` case in both `AlertDirection` switches
- EasyCrypto/BackgroundTasks/CandleAlertRefresher.swift: new throttled (≥1h) refresher — evaluate, persist `lastCandleDropOpenTime`, log `NotificationLogEntry`, stamp `lastCheckedAt`, all in one save
- EasyCrypto/EasyCryptoApp.swift: build `CandleAlertService` (inject `fetchKlines`), register `CandleAlertState.self`, run `CandleAlertRefresher` in the background task
- EasyCrypto/Features/Settings/NotificationLogView.swift: icon/tint/label for `candleDrop` + direction-aware value label (P&L vs Price)
- EasyCryptoTests: CandleDropTests (5), CandleAlertServiceTests (5), CandleAlertStateTests (2), CandleAlertRefresherTests (3)

## Check for Understanding

1. How is "2 consecutive candles dropping" defined in this advance, and where is
   that rule isolated so the alternative (bearish-candle) reading could be swapped?
2. Why are 4 candles fetched when only 3 closes are needed to detect two consecutive
   lower closes, and why is the in-progress candle excluded?
3. Why is the "every hour" requirement implemented as a `lastCheckedAt` throttle
   rather than a guaranteed hourly timer, given the iOS background model?
4. What two pieces of state prevent duplicate candle-drop notifications (one per
   coin, one global), and which model holds each?
5. How does a fired candle-drop alert end up in the Settings Notification Log, and
   which prior advance does that reuse?
