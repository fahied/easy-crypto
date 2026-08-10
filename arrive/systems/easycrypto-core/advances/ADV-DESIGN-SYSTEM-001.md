---
advance:
  id: ADV-DESIGN-SYSTEM-001
  title: Margin P&L display components — GlassCard variants for margin positions
  system: easycrypto-core
  primary_component: design-system
  components:
  - design-system
  started_at: 2026-08-08T04:00:00Z
  started_by: null
  implementation_completed_at: 2026-08-09T09:16:00Z
  implementation_completed_by: null
  updated_by: null
  archived_at: null
  archived_by: null
  review_time_estimate_minutes: 15
  pr_links: []
  reviewability_score: 6
  risk_flags: []
  evidence:
  - tidy:preparatory
  - tdd:red-green
  - tests:unit (24 tests — 15 MarginDesignSystemTests + 9 MarginFIFOCalculatorTests)
  status: complete
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

## Planned Implementation Tasks

- [x] test: `TradingModeBadge` renders correct text and color per mode
- [x] test: `MarginPnLLabel` shows fee subtitle when fee > 0
- [x] test: `MarginPnLLabel` falls back to standard PnLLabel when fee is nil
- [x] test: `MarginHoldingRow` shows borrowed quantity and liquidation price
- [x] test: `MarginHoldingRow` hides margin columns in spot mode
- [x] test: `Theme.marginCross` and `Theme.marginIsolated` are accessible
- [x] tidy: add `marginCross` and `marginIsolated` to `Theme`
- [x] tidy: add `TradingModeBadge` view
- [x] tidy: add `MarginPnLLabel` view
- [x] tidy: add `MarginHoldingRow` view

## Check for Understanding

1. Why does `MarginPnLLabel` compose `PnLLabel` rather than duplicating its formatting
    logic, and what SwiftUI mechanism enables this composition?
2. How does the conditional display of liquidation price in `MarginHoldingRow` relate
    to the structural difference between cross-margin and isolated-margin in Binance's
    API?
3. Why are margin colors added to `Theme` as static properties rather than being
    hardcoded in the new views?

## Risk + Rollback

- Risk: additive views and theme colors. No existing component behavior changes.
- Rollback: revert commits. New views become unused code.

## Evidence

- [ ] tidy:preparatory
- [ ] tdd:red-green
- [ ] tests:unit (24 tests: 15 MarginDesignSystemTests + 9 MarginFIFOCalculatorTests)

## Changes Made

### 2026-08-09: ADV-CORE-SERVICES-008 & ADV-DESIGN-SYSTEM-001 complete: margin FIFO calculator + display components (Theme colors, TradingModeBadge, MarginPnLLabel, MarginHoldingRow) — 24 tests passing

**feat**

- `arrive/systems/easycrypto-core/advances/ADV-DESIGN-SYSTEM-001.md`: Modified

