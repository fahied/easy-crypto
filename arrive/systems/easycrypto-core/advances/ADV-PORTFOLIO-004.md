---
advance:
  id: "ADV-PORTFOLIO-004"
  title: "Remove holdings list from Portfolio tab — Holdings tab is single source of truth"
  system: "easycrypto-core"
  primary_component: "portfolio"
  components: ["portfolio", "holdings"]
  depends_on: ["ADV-PORTFOLIO-003"]
  started_at: "2026-08-10"
  implementation_completed_at: "2026-08-10"
  review_time_estimate_minutes: 15
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 15
  risk_flags: []
  evidence: ["tidy:removed-dead-code", "preview:updated"]
  model_usage: []
  status: complete
---

## Objective

The Portfolio tab currently shows summary metric cards **and** a holdings
list at the bottom. The holdings list duplicates what the dedicated Holdings
tab already provides.

After this advance, the Portfolio tab shows **only summary metric cards**.
The holdings list is removed entirely. The Holdings tab becomes the single
source of truth for per-asset detail.

## Behavioral Change

After this advance:

- Portfolio tab contains **only** summary metric cards (Total Invested, Current
  Value, Total P&L, Unrealized P&L, Realized P&L) with per-mode breakdown.
- No holdings list, no asset rows, no per-asset detail on the Portfolio tab.
- Holdings tab is the **only** place to see individual assets, their quantities,
  unrealized P&L, and realized P&L breakdown.
- A "View Holdings →" link or button on the Portfolio tab navigates to the
  Holdings tab for users who want per-asset detail.
- The Holdings tab retains its full functionality: mode picker (Spot / Cross
  Margin / Isolated Margin), search/filter, per-asset rows with FIFO detail.

## Risk + Rollback

- **Risk**: Users who relied on the Portfolio tab for per-asset detail must
  navigate to the Holdings tab instead. Mitigated by a "View Holdings" link.
- **Risk**: PortfolioSummary previously aggregated from `holdings:` init; after
  removal, it relies on the processor's `computeSummary()` path, which already
  works correctly (ADV-PORTFOLIO-003 validated this).
- **Rollback**: Re-add `holdings` and `holdingsCount` to `PortfolioState` and
  restore the holdings list section in `PortfolioView`. All changes are
  localized to `PortfolioState` and `PortfolioView`.

## Evidence

- `PortfolioSummary.isEmpty` computed property added (derived from `holdingsCount`)
- `PortfolioView` updated — `holdings:` initializer argument removed from preview
- `PortfolioState` — `holdings` and `holdingsCount` properties removed
- `PortfolioView` — holdings list section already removed by ADV-PORTFOLIO-003

## Check for Understanding

1. Where does the Portfolio tab get its total invested value, current value, and
   P&L numbers after this advance?
2. Which tab should a user navigate to in order to see individual asset rows?
3. What property on `PortfolioSummary` determines whether the empty state is
   shown?
4. Why was the `holdings` property removed from `PortfolioState` instead of
   just being ignored in the view?

## Planned Implementation Tasks

- [x] Remove `holdings` and `holdingsCount` from `PortfolioState`
- [x] Add `isEmpty` computed property to `PortfolioSummary`
- [x] Update `PortfolioView` to use `isEmpty` instead of removed properties
- [x] Update PortfolioView previews — remove `holdings:` initializer argument
- [x] Verify build compiles cleanly

## Bug Fixes

(none)

## Changes Made

- 2026-08-10: Removed holdings list from Portfolio tab — PortfolioView now
  shows only summary metric cards. Holdings tab is single source of truth for
  per-asset detail. `PortfolioState.holdings` and `holdingsCount` removed;
  `PortfolioSummary.isEmpty` computed property added.

## CI Evidence Notes

Run `xcodebuild -scheme EasyCrypto -destination 'platform=iOS Simulator,name=iPhone 17' build`
to verify compilation.
