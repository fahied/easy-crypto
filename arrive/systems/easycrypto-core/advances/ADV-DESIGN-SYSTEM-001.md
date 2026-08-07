---
advance:
  id: "ADV-DESIGN-SYSTEM-001"
  title: "Margin P&L display components — GlassCard variants for margin positions"
  system: "easycrypto-core"
  primary_component: "design-system"
  components: ["design-system", "trade-history", "portfolio", "holdings"]
  started_at: "2026-08-07T09:00:00Z"
  implementation_completed_at: ~
  review_time_actual_minutes: ~
  pr_links: []
  reviewability_score: 0
  risk_flags: []
  evidence: []
  model_usage: []
  status: planned
---

## Objective

Extend the design system with margin-specific visual components: a `TradingModeBadge`
for mode indicators, a `MarginPnLLabel` that shows margin-adjusted P&L with borrowing
fee context, and a `MarginHoldingRow` that displays borrowed quantity and liquidation
price alongside standard holding data. Depends on ADV-PORTFOLIO-002 (margin holdings),
ADV-TRADE-HISTORY-001 (margin trade history), and ADV-CORE-SERVICES-008 (margin P&L).

## Behavioral Change

After this advance:

- New `TradingModeBadge` view: small pill-shaped badge with color per mode:
  - Spot: blue (`Theme.accent`)
  - Cross Margin: orange (`Theme.loss` tinted)
  - Isolated Margin: purple (new theme color)
- New `MarginPnLLabel` view: extends `PnLLabel` with an optional `borrowingFee` parameter
  that shows a small "+ fee" indicator when the fee is non-zero:
  - Format: "−$123.45 P&L (fee: $12.34)" when fee > 0
  - Falls back to standard `PnLLabel` when fee is nil or zero
- New `MarginHoldingRow` view: extends `TradeRowView` with additional columns for:
  - Borrowed quantity (e.g., "0.5 borrowed")
  - Liquidation price (e.g., "Liq: $45,230")
  - Shown only for `.crossMargin` and `.isolatedMargin` modes; hidden for `.spot`
- `Theme` gains margin-specific colors:
  - `marginCross: Color` — orange tint for cross-margin elements
  - `marginIsolated: Color` — purple tint for isolated-margin elements
- All new components are additive — existing views using `PnLLabel`, `TradeRowView`,
  and `GlassCard` are untouched.

## Design Notes

- **Badge as a view, not a string**: `TradingModeBadge` is a proper SwiftUI view
  so it can participate in the Liquid Glass design system. It uses a `Label` with
  a small colored circle and the mode name.
- **MarginPnLLabel wraps PnLLabel**: Rather than duplicating the P&L formatting logic,
  `MarginPnLLabel` composes `PnLLabel` and adds a fee subtitle. This keeps formatting
  consistent and avoids code duplication.
- **Liquidation price is conditional**: Isolated-margin positions have a liquidation
  price; cross-margin positions do not (it's a portfolio-level metric). The
  `MarginHoldingRow` shows the liquidation price only when non-nil.
- **Borrowed quantity indicator**: Shown as a small amber tag next to the asset name,
  using the existing `Theme.loss` color as a warning indicator.
- **Theme extension**: Margin colors are added as static properties on `Theme` so
  they're accessible everywhere without import cycles.

## Component Impact

- **design-system** (`EasyCrypto/DesignSystem/`):
  - `Theme.swift` — add `marginCross` and `marginIsolated` colors
  - New `TradingModeBadge.swift` — mode indicator badge
  - New `MarginPnLLabel.swift` — P&L label with borrowing fee display
  - New `MarginHoldingRow.swift` — holding row with margin-specific columns

- **portfolio** (`EasyCrypto/Features/Portfolio/`):
  - Views use `TradingModeBadge` and `MarginPnLLabel` in margin mode

- **trade-history** (`EasyCrypto/Features/TradeHistory/`):
  - Trade rows use `TradingModeBadge` and `MarginPnLLabel` for margin trades

- **holdings** (`EasyCrypto/Features/Holdings/`):
  - Holding rows use `MarginHoldingRow` in margin mode

## Out of Scope

- Margin-specific chart components (separate advance)
- Liquidation price animation/warning (separate advance)
- Dark/light mode margin color variants (uses existing theme colors)
- Margin mode onboarding illustrations

## Planned Implementation Tasks

- [ ] test: `TradingModeBadge` renders correct text and color per mode
- [ ] test: `MarginPnLLabel` shows fee subtitle when fee > 0
- [ ] test: `MarginPnLLabel` falls back to standard PnLLabel when fee is nil
- [ ] test: `MarginHoldingRow` shows borrowed quantity and liquidation price
- [ ] test: `MarginHoldingRow` hides margin columns in spot mode
- [ ] test: `Theme.marginCross` and `Theme.marginIsolated` are accessible
- [ ] tidy: add `marginCross` and `marginIsolated` to `Theme`
- [ ] tidy: add `TradingModeBadge` view
- [ ] tidy: add `MarginPnLLabel` view
- [ ] tidy: add `MarginHoldingRow` view

## Bug Fixes

- [ ] None

## Risk + Rollback

- Risk: additive views and theme colors. No existing component behavior changes.
- Rollback: revert commits. New views become unused code.

## Evidence

- [ ] tidy:preparatory
- [ ] tdd:red-green
- [ ] tests:unit (MarginDesignSystemTests — target 5 tests)

## CI Evidence Notes

- If CI jobs are enabled, link pipeline evidence (`ci:passed`) from PR/MR and
  default-branch runs.
- If CI jobs are temporarily disabled, run checks externally before merge:
  - `arrive pr check --strict --json`
  - `arrive evidence record --advance ADV-DESIGN-SYSTEM-001 --status passed`

## Changes Made

*(populated during implementation)*

## Check for Understanding

1. Why does `MarginPnLLabel` compose `PnLLabel` rather than duplicating its formatting
    logic, and what SwiftUI mechanism enables this composition?
2. How does the conditional display of liquidation price in `MarginHoldingRow` relate
    to the structural difference between cross-margin and isolated-margin in Binance's
    API?
3. Why are margin colors added to `Theme` as static properties rather than being
    hardcoded in the new views?
