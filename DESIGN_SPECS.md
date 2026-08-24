# EasyCrypto — Design Specifications

> **Platform:** iOS 26+
> **Language:** Swift 6.2
> **UI Framework:** SwiftUI with iOS 26 Liquid Glass design
> **Bundle ID:** `com.fahied.EasyCrypto`

---

## 1. Design Philosophy

EasyCrypto is a **read-only Binance portfolio tracker** — no trading, no WebSocket, no cloud sync. Every pixel should communicate trust, clarity, and financial precision. The design borrows from the Binance brand palette (gold accent on dark glass) while respecting iOS 26 Liquid Glass conventions.

**Core principles:**
- **Data first, decoration second** — financial numbers must be scannable at a glance
- **Glass as structure, not just effect** — every glass card should group related information, not exist for aesthetics alone
- **P&L is a color** — profit/loss is communicated through color before the user reads a single number
- **Dark mode by default** — aligns with crypto app conventions; respects system setting when overridden
- **Accessibility-aware** — Dynamic Type, VoiceOver labels, and sufficient contrast on all critical elements

---

## 2. Color System

### 2.1 Semantic Palette

All colors live in `DesignSystem/Theme.swift`. Do not hardcode colors in views.

| Token | Value | Usage |
|---|---|---|
| `Theme.accent` | `#F0B90B` (gold) | Primary actions, active states, Binance brand alignment |
| `Theme.profit` | `#21D471` (green) | Positive P&L, buy side, success states |
| `Theme.loss` | `#FF4757` (red) | Negative P&L, sell side, destructive actions |
| `Theme.neutral` | `Color.secondary` | Zero-value P&L, disabled states, secondary text |
| `Theme.marginCross` | `#FB7D21` (orange) | Cross-margin badge, borrowed quantity |
| `Theme.marginIsolated` | `#9966FA` (purple) | Isolated-margin badge |

### 2.2 Platform Colors

- **Backgrounds:** System background (adapts to light/dark). Dark mode is the expected primary usage.
- **Text:** `.primary` for body, `.secondary` for labels, `.tertiary` for footers and timestamps
- **Borders/Overlays:** `Color.white.opacity(0.12)` for glass card stroke borders
- **Fill materials:** `.ultraThinMaterial` inside glass cards

### 2.3 Color Usage Rules

- Profit/loss colors are **never** used for non-financial indicators (e.g., don't use `Theme.profit` for a "connected" status that isn't financial)
- Gold accent (`Theme.accent`) is reserved for **one primary action per screen** — don't accent multiple buttons simultaneously
- Margin colors (`marginCross`, `marginIsolated`) are **never** used for spot holdings
- All P&L text must use semantic colors, not hardcoded green/red values

---

## 3. Typography

### 3.1 Type Scale

| Role | Font | Weight | Use |
|---|---|---|---|
| Screen title | `.title` | `.bold` | Navigation bar titles |
| Section heading | `.headline` | `.semibold` | Card section labels, form labels |
| Card value | `.title3` | `.bold` | KPI values in `MetricCard` |
| Body text | `.subheadline` | `.regular` | Holding names, subtitles |
| Detail text | `.callout` | `.regular` | Insight bodies, descriptions |
| Caption | `.caption` | `.regular` | Labels, metadata |
| Small caption | `.caption2` | `.medium` | Trade dates, P&L pills, secondary metrics |
| Monospaced numbers | `.monospacedDigit()` | varies | All financial values (prices, P&L, quantities) |

### 3.2 Number Formatting

All monetary formatting lives in `Theme.swift` extensions on `Double`. Views must use these, never format inline.

| Helper | Format | Example |
|---|---|---|
| `.usdtFormatted` | `$1,234.56` (2 decimal places, thousands separator) | Trade total, invested value |
| `.signedUsdtFormatted` | `+$1,234.56` / `-$1,234.56` | P&L values |
| `.percentFormatted` | `+12.34%` / `-5.67%` | P&L percentage |
| `.quantityFormatted` | 4 decimals if `≥1`, 8 decimals if `<1` | Coin quantities |
| `.priceFormatted` | 2 decimals if `≥$1`, 4 if `≥$0.01`, 8 otherwise | Current price, avg buy price |

### 3.3 Typography Rules

- All financial values use `.monospacedDigit()` to prevent layout jitter during refresh
- Negative signs must use the standard minus character, not an em dash
- Percentages always show sign (`+`/`-`), even in subtitle positions
- Line limits: `.lineLimit(1)` on KPI values, `.minimumScaleFactor(0.7)` to prevent truncation

---

## 4. Spacing & Layout

### 4.1 Spacing Tokens

| Token | Value | Usage |
|---|---|---|
| `Theme.cardSpacing` | `12pt` | Gap between cards in grids and stacks |
| `Theme.sectionSpacing` | `20pt` | Vertical gap between major sections |
| `Theme.cardRadius` | `20pt` | Corner radius on standard glass cards |
| `Theme.smallRadius` | `12pt` | Corner radius on compact elements (holding rows) |

### 4.2 Layout Patterns

**ScrollView with horizontal padding:**
All tab content uses `ScrollView` with `.scrollIndicators(.hidden)`, `.padding(.horizontal)`, and `.padding(.bottom, 20)`. Section spacing is `Theme.sectionSpacing`.

**LazyVGrid for metric cards:**
2-column grid with `GridItem(.flexible())` and `spacing: Theme.cardSpacing`. Used in Portfolio tab summary and Settings sync stats.

**HStack for inline rows:**
Trade rows, holding rows, and alert config rows use `HStack(spacing: 12)` with `Spacer()` for alignment.

### 4.3 Responsive Behavior

- Metric cards use `.minimumScaleFactor(0.7)` on values to handle small screens
- No explicit width constraints on content — let SwiftUI flow naturally
- On iPad, the 2-column metric grid remains 2 columns (doesn't expand to 3–4)

---

## 5. Glass Design System

### 5.1 GlassCard (`GlassCard.swift`)

The `glassCard()` view modifier is the foundational container. It applies:

- `.ultraThinMaterial` background fill
- `RoundedRectangle(cornerRadius:)` clip shape
- Subtle white stroke border (`opacity(0.12)`, lineWidth: 1)
- Full-width alignment with internal padding

**Usage rules:**
- Every section of every tab should be wrapped in a `GlassCard` or `MetricCard`
- Do not stack glass cards directly — always include at least `Theme.cardSpacing` between them
- Do not nest glass cards more than 2 levels deep
- Long content inside glass cards should use `VStack(alignment: .leading)` with proper spacing

### 5.2 MetricCard (`MetricCard.swift`)

A specialized glass card for single KPIs. Structure:

```
VStack(alignment: .leading, spacing: 6)
  ├── Label (font: .caption, color: .secondary)
  ├── Value (font: .title3.bold, color: valueColor)
  └── Subtitle (font: .caption2, color: .secondary, optional)
```

**Usage rules:**
- Always show a `label` — a card with only a value is ambiguous
- Subtitle is optional but recommended for context (e.g., "Across 5 assets")
- `valueColor` defaults to `.primary`; use `Theme.profit` or `Theme.loss` for P&L values

### 5.3 Glass in Navigation

- Tab bar uses system default glass styling (no custom override)
- Navigation bars are standard `NavigationStack` — do not apply glass effects to nav bars
- `NavigationLink` rows in Settings use `.buttonStyle(.plain)` with `.glassCard()` on the label container

---

## 6. Component Library

### 6.1 PnLLabel

Displays a P&L value with optional percentage and directional arrow.

**Structure:**
```
HStack(spacing: 4)
  ├── Arrow SF Symbol (arrow.up.right / arrow.down.right) [optional]
  ├── Value text (signedUsdtFormatted)
  └── Percentage text in parentheses [optional]
```

**Behavior:**
- Green for positive, red for negative, neutral color for zero
- Arrow hidden when `showArrow == false`
- Percentage always shown in parentheses with reduced opacity (`opacity(0.75)`)
- Default font: `.subheadline.bold()`

### 6.2 MarginPnLLabel

Extends `PnLLabel` with an optional borrowing fee subtitle.

**Structure:**
```
VStack(alignment: .trailing, spacing: 2)
  ├── PnLLabel (same as above)
  └── Fee text ("fee: $XX.XX") [if fee > 0]
```

**Behavior:**
- Fee line only appears when `borrowingFee > 1e-12` (avoids floating-point noise)
- Fee text uses `Theme.loss.opacity(0.7)` to indicate cost without overpowering the P&L
- Falls back to standard `PnLLabel` behavior when fee is nil or zero

### 6.3 TradeRowView

A reusable row for trade list display.

**Structure:**
```
HStack(spacing: 12)
  ├── Side label ("BUY" / "SELL") — 36pt wide, bold caption
  ├── Date + price column (VStack, aligned leading)
  ├── Spacer()
  └── Quantity + total column (VStack, aligned trailing)
```

**Styling:**
- BUY side uses `Theme.profit`, SELL uses `Theme.loss`
- Date: `.formatted(date: .abbreviated, time: .shortened)` in `.secondary` color
- Price: `.usdtFormatted` prefixed with "@ "
- Total: `.usdtFormatted` in `.secondary` color
- Typically wrapped in `.glassCard()` when used in lists

### 6.4 TradingModeBadge

A pill-shaped badge for Spot / Cross Margin / Isolated Margin.

**Structure:**
```
HStack(spacing: 5)
  ├── 8pt circle in mode color
  └── Display name text in mode color
    └── Background: rounded rect with 0.12 opacity fill + 0.25 opacity stroke
```

**Color mapping:**
- `.spot` → `Theme.accent`
- `.crossMargin` → `Theme.marginCross`
- `.isolatedMargin` → `Theme.marginIsolated`

### 6.5 MarginHoldingRow

A holding row variant with margin-specific columns.

**Structure:**
```
VStack(spacing: 8)
  ├── Header (HStack)
  │   ├── Asset name + quantity (leading)
  │   ├── Spacer()
  │   └── Current value + P&L pill (trailing)
  ├── Divider (white opacity 0.08)
  └── Stats strip (HStack)
      ├── Avg Buy
      ├── Market price
      ├── Borrowed [margin only, if > 0]
      └── Liq. Price [margin only, if non-empty]
```

**Behavior:**
- Margin detail columns only appear when `tradingMode != .spot`
- Borrowed line hidden when `nil` or `≤ 1e-12`
- Liquidation price line hidden when `nil` or empty string
- P&L pill: capsule background with `pnlColor.opacity(0.14)`, showing signed P&L + percent

---

## 7. Screen Specifications

### 7.1 Portfolio Tab

**Purpose:** Dashboard overview with summary KPIs and a scrollable holdings list.

**Layout:**
```
NavigationStack
  └── ScrollView
       └── VStack(spacing: sectionSpacing)
            ├── summaryGrid (LazyVGrid, 2 columns)
            │    ├── MetricCard: "Total Invested" + asset count subtitle
            │    ├── MetricCard: "Current Value"
            │    ├── MetricCard: "Total P&L" + percent subtitle (colored)
            │    ├── MetricCard: "Unrealized P&L" + percent subtitle (colored)
            │    └── MetricCard: "Realized P&L" (colored)
            └── lastRefreshFooter ("Updated 2 hours ago", .tertiary)
```

**States:**
- **Loading:** Centered `ProgressView` + "Syncing trades…" text
- **Empty:** `ContentUnavailableView` with "No Holdings" title, pull-to-refresh prompt, "Refresh Now" button tinted `Theme.accent`
- **Error:** `ContentUnavailableView` with "Something Went Wrong", error message, "Try Again" button
- **Loaded:** Metric grid + refresh footer

**Toolbar:** Refresh button in `.primaryAction` placement — shows `ProgressView` during sync, `arrow.clockwise` otherwise. Disabled during loading.

**Pull-to-refresh:** Triggers `processor.handle(.refresh)` which syncs trades AND fetches prices.

**Animation:** Summary grid animates with `.spring(duration: 0.4)` on `totalCurrentValueUSDT` changes.

### 7.2 Holdings Tab

**Purpose:** Per-coin list with avg cost, current price, quantity, and P&L. Tap → Coin Detail.

**Layout:**
```
NavigationStack
  └── HoldingsListView
       └── ScrollView
            └── VStack(spacing: Theme.cardSpacing)
                 └── ForEach(holdings)
                      └── MarginHoldingRow (or standard HoldingRow for spot)
```

**Sorting:** Holdings sortable by name, value, P&L amount, P&L percentage via a sort picker in the toolbar or list header.

**Navigation:** Tap a row → push `CoinDetailView`.

**States:**
- Loading, empty, error states same as Portfolio
- When no holdings exist, show "Pull down to refresh" in the empty state

### 7.3 Coin Detail Screen

**Purpose:** Deep dive into a single coin — summary, chart, trade history.

**Layout:**
```
NavigationStack (pushed from Holdings)
  └── ScrollView
       └── VStack(spacing: Theme.sectionSpacing)
            ├── Summary glass card
            │    ├── Weighted avg buy price
            │    ├── Quantity held
            │    ├── Total invested
            │    ├── Current value
            │    └── Unrealized P&L (colored)
            ├── Chart section
            │    ├── Interval picker (1h, 4h, 1d, 1w)
            │    └── Swift Charts line chart
            └── Trade list
                 └── ForEach(trades)
                      └── TradeRowView (in glass cards)
```

**Chart:** Swift Charts line chart showing price over selectable intervals. Data from `BinanceAPIClient.fetchKlines`.

**Navigation title:** Coin asset name (e.g., "Bitcoin" or "BTC").

### 7.4 Trade History Tab

**Purpose:** Chronological trade list grouped by date, filterable by coin.

**Layout:**
```
NavigationStack
  └── ScrollView
       └── VStack(spacing: Theme.cardSpacing)
            ├── Coin filter chips (horizontal scroll)
            └── Date-grouped trade list
                 └── ForEach(dates)
                      ├── Date header ("Today", "Yesterday", "Aug 20, 2026")
                      └── ForEach(trades on date)
                           └── TradeRowView
```

**Trade row styling:**
- BUY label in `Theme.profit`, SELL in `Theme.loss`
- Date format: relative for trades within 24 hours, formatted date for older
- Wrapped in glass cards for visual grouping

### 7.5 Insights Tab

**Purpose:** On-device AI-generated trading insights + profit breakdown + conversational chat.

**Layout:**
```
ScrollView
  └── VStack(spacing: Theme.sectionSpacing)
       ├── ProfitBreakdownView (auto-refreshes on tab open)
       ├── Header card
       │    ├── "AI Insights" label + "brain.head.profile" icon
       │    ├── Description text
       │    ├── Last updated timestamp
       │    ├── "Analyze" button (borderedProminent, Theme.accent)
       │    └── "Ask a question" button (bordered)
       ├── State-dependent content:
       │    ├── .disabled → "Insights are turned off" message card
       │    ├── .unavailable → "On-device AI unavailable" message card
       │    ├── .ready, empty → "No insights yet" message card
       │    └── .ready, populated → ForEach(insightItems) { insightCard }
       └── Footer: "Processed on device — your trades never leave your iPhone."
```

**Insight card structure:**
```
glassCard
  ├── HStack: category icon + title + optional symbol pill
  ├── Body text (.callout, .secondary)
  └── Category label (.caption2, severity color)
```

**Chat:** Presented as a `.sheet` with `NavigationStack` + `InsightChatView`.

**Availability states:**
- `.disabled` — insights toggle is off in Settings
- `.unavailable(reason)` — Apple Intelligence not available on device
- `.ready` — normal operation

**Footer:** Always shown, reinforces privacy message with `lock.shield` icon.

### 7.6 Settings Tab

**Purpose:** API credentials, connection testing, trading mode, sync stats, alerts, AI toggle, danger zone.

**Layout:**
```
ScrollView
  └── VStack(spacing: Theme.sectionSpacing)
       ├── API Credentials (glassCard)
       │    ├── "API Credentials" label + key icon
       │    ├── [if hasApiKey] "API key configured" + Remove button
       │    └── [if no key] SecureFields for API Key + Secret + Save button
       ├── Connection (glassCard)
       │    ├── "Connection" label + network icon
       │    └── Status view + Test button
       ├── Trading Mode (glassCard)
       │    ├── "Trading Mode" label + cycle icon
       │    ├── Segmented picker (Spot / Cross Margin / Isolated Margin)
       │    └── Warning text for margin modes
       ├── Sync Stats (glassCard)
       │    ├── "Sync Stats" label + bar chart icon
       │    └── 2-column grid: Total Trades + Synced Symbols
       ├── Price Alerts (glassCard)
       │    ├── "Price Alerts" label + bell icon
       │    ├── Enable Notifications button [if not authorized]
       │    └── Per-coin alert rows (toggle + threshold fields)
       ├── Notification Log (glassCard, NavigationLink)
       │    └── "Notification Log" + chevron
       ├── AI Insights (glassCard)
       │    ├── "AI Insights" label + brain icon
       │    ├── Toggle for on-device insights
       │    └── Privacy description text
       └── Danger Zone (glassCard, loss-tinted)
            ├── "Danger Zone" label + warning icon
            └── "Clear All Data" destructive button
```

**Connection status states:**
- `.idle` → "Not tested" with `minus.circle`
- `.testing` → ProgressView + "Testing…"
- `.success` → "Connected" with `checkmark.circle.fill`, green
- `.failed` → "Failed" with `xmark.circle.fill`, red + error message

**Alert rows:** Expandable — when toggled on, show two text fields: profit threshold (USDT) and percent threshold (%). Fields use `.decimalPad` keyboard.

### 7.7 Onboarding Flow

**Trigger:** No API key in Keychain → show onboarding instead of main tabs.

**Layout:**
```
NavigationStack ("Setup")
  └── VStack(spacing: 32)
       ├── Spacer()
       ├── Large icon (chart.line.uptrend.xyaxis, 64pt, Theme.accent)
       ├── "Welcome to EasyCrypto" (title.bold)
       ├── "Add your Binance API credentials to get started." (subheadline, .secondary)
       ├── Spacer()
       ├── Embedded SettingsView (API credential form)
       └── Spacer()
```

**Transition:** When API key is saved, `NotificationCenter` posts `.apiKeyChanged` → `ContentView` re-checks Keychain → transitions to main tab view.

---

## 8. Design Tokens Summary

```
// Colors
Theme.accent              → #F0B90B (gold)
Theme.profit              → #21D471 (green)
Theme.loss                → #FF4757 (red)
Theme.neutral             → Color.secondary
Theme.marginCross         → #FB7D21 (orange)
Theme.marginIsolated      → #9966FA (purple)

// Radii
Theme.cardRadius          → 20pt
Theme.smallRadius         → 12pt

// Spacing
Theme.cardSpacing         → 12pt
Theme.sectionSpacing      → 20pt

// Glass
Background fill           → .ultraThinMaterial
Stroke border             → Color.white.opacity(0.12), lineWidth: 1
Card inner padding        → 16pt (cardSpacing + 4)
```

---

## 9. Iconography

All icons use SF Symbols. Never use custom image assets for standard icons.

| Icon | Usage |
|---|---|
| `chart.pie.fill` | Portfolio tab |
| `bitcoinsign.circle.fill` | Holdings tab |
| `clock.fill` | History tab |
| `brain.head.profile` | Insights tab |
| `gearshape.fill` | Settings tab |
| `arrow.clockwise` | Refresh action |
| `arrow.up.right` / `arrow.down.right` | P&L direction arrows |
| `checkmark.circle.fill` | Success states |
| `xmark.circle.fill` | Failure states |
| `exclamationmark.triangle` | Error/warning states |
| `bell.fill` / `bell.badge.fill` | Price alerts |
| `key.fill` | API credentials |
| `network` | Connection testing |
| `arrow.triangle.2.circlepath` | Trading mode |
| `chart.bar.fill` | Sync stats |
| `lock.shield` | On-device privacy |
| `sparkles` / `wand.and.stars` | AI actions |
| `bubble.left.and.bubble.right` | Chat |
| `trash.fill` | Clear data (destructive) |
| `chart.line.uptrend.xyaxis` | Welcome icon, performance |

---

## 10. Interaction Patterns

### 10.1 Pull-to-Refresh

- Exclusive refresh mechanism — no toolbar refresh button on Portfolio tab
- `.refreshable` modifier on ScrollView
- Single action syncs trades AND fetches latest prices
- Loading state shown via system pull-to-refresh spinner
- Disabled during active sync to prevent duplicate requests

### 10.2 Button Styles

| Style | Modifier | Usage |
|---|---|---|
| Primary action | `.borderedProminent().tint(Theme.accent)` | Save credentials, Refresh, Analyze, Test Connection |
| Secondary action | `.bordered()` | Test, Ask a question, Remove key |
| Destructive | `.bordered().tint(Theme.loss)` | Clear All Data |
| Toggle accent | `.tint(Theme.accent)` | All toggles (alerts, AI insights) |

**Rule:** One `borderedProminent` button per card/section max. Don't create multiple competing primary actions.

### 10.3 Navigation

- `NavigationStack` for all tab root views
- `NavigationLink` for drill-down (Holdings → Coin Detail, Settings → Notification Log)
- Sheets for modal content (Insights chat)
- No custom navigation bars — use system `.navigationTitle()` and `.navigationBarTitleDisplayMode(.inline)` where appropriate

### 10.4 Loading & Error States

Every async screen must handle three states:

| State | Pattern |
|---|---|
| Loading | Centered `ProgressView` + status text, OR pull-to-refresh spinner |
| Error | `ContentUnavailableView` with error message + retry button |
| Empty | `ContentUnavailableView` with descriptive text + action button |

Error banners (for refresh failures with cached data) auto-dismiss after 4 seconds — implemented in the processor, not the view.

---

## 11. Margin Trading Design (Planned)

### 11.1 Trading Mode Switching

- Segmented picker in Settings: Spot / Cross Margin / Isolated Margin
- Current selection persisted; app behavior changes based on mode
- Orange warning text when margin mode selected: "Margin trading requires margin to be enabled on your Binance account."

### 11.2 Margin Visual Differentiation

| Element | Spot | Cross Margin | Isolated Margin |
|---|---|---|---|
| Badge color | `Theme.accent` | `Theme.marginCross` | `Theme.marginIsolated` |
| Holding row | Standard `HoldingRow` | `MarginHoldingRow` with borrowed + liq. price | `MarginHoldingRow` with borrowed + liq. price |
| P&L label | `PnLLabel` | `MarginPnLLabel` with fee subtitle | `MarginPnLLabel` with fee subtitle |
| Trade row | `TradeRowView` | `TradeRowView` + `TradingModeBadge` | `TradeRowView` + `TradingModeBadge` |

### 11.3 Margin Components (Planned)

The following components are designed and tested but not yet wired to live data:

- `TradingModeBadge` — pill badge with mode-specific color
- `MarginPnLLabel` — P&L with borrowing fee subtitle
- `MarginHoldingRow` — extended holding row with borrowed qty and liquidation price columns

Tests exist in `EasyCryptoTests/DesignSystem/MarginDesignSystemTests.swift` covering:
- Theme color distinctness
- Badge color mapping per mode
- Fee subtitle visibility logic
- Margin detail column show/hide logic per trading mode

---

## 12. Dark / Light Mode

- App launches in dark mode (`.preferredColorScheme(.dark)` in `EasyCryptoApp`)
- No forced color scheme override — respects system setting
- All colors use semantic names (`.primary`, `.secondary`, `.tertiary`) where possible
- Glass card stroke border uses `Color.white.opacity(0.12)` — this works in both modes but is tuned for dark
- If light mode support needs tuning, add a `.colorScheme(.dark)` modifier to individual screens rather than globally

---

## 13. Preview Strategy

Every SwiftUI view and reusable component must include `#Preview` blocks covering:

| Preview State | When Required |
|---|---|
| Happy path | Always — populated data, normal interaction |
| Empty state | Any view that can have zero items |
| Error state | Any view that displays errors inline |
| Loading state | Any view with async data fetching |
| Variant states | Components with visual variants (e.g., PnLLabel: positive / negative / zero) |

**Preview data:** In-memory `ModelContainer` seeded with `PreviewSampleData`. Never use the live persistence store.

**Naming:** Descriptive names like `#Preview("Positive P&L")`, `#Preview("Empty Portfolio")`.

**Dark mode:** All previews explicitly set `.preferredColorScheme(.dark)`.

---

## 14. Accessibility

| Requirement | Implementation |
|---|---|
| Dynamic Type | All fonts use SwiftUI dynamic type scaling; test at `.large` and `.accessibilityMedium` |
| VoiceOver | SF Symbols include accessibility labels by default; add custom labels for P&L values |
| Color contrast | Profit/loss colors meet WCAG AA against glass card backgrounds |
| Touch targets | All interactive elements ≥ 44pt height |
| Reduced motion | Respect `Reduce Motion` accessibility setting for chart animations |
| Reduce transparency | Glass effects should degrade gracefully — ultraThinMaterial respects this system setting |

---

## 15. Implementation Notes

### 15.1 Architecture

The app uses MVI (Model-View-Intent) with `@Observable` state and `@MainActor` processors. Views are pure SwiftUI — they render state and send intents, never mutate state directly.

Per feature: `*Intent.swift`, `*State.swift`, `*Processor.swift`, `*View.swift`.

### 15.2 Dependency Injection

Services use the struct-with-closures pattern (no protocols). Each service ships `live`, `preview`, and `noop` values. Processors receive services via initializer injection.

### 15.3 Persistence

SwiftData `@Model` classes: `Trade`, `SyncMetadata`, `PriceAlertConfig`, `NotificationLogEntry`, `CandleAlertState`, `AccountBalance`, `MarginBalance`, `CrossMarginBalance`, `TradingInsight`, `InsightState`.

ModelContainer configured once in `EasyCryptoApp` and injected via `.modelContainer()` modifier.

### 15.4 Background Tasks

- Price alert checks: ~5 minute `BGAppRefreshTask` cadence
- Candle drop alerts: hourly within the same background task
- AI Insight regeneration: ~4 hour cadence, same task chain
- Background task scheduled on `.background` scene phase transition

### 15.5 Testing

Swift Testing framework (`@Suite`, `@Test`, `#expect`). TDD with BDD naming (Given/When/Then). Coverage targets: ≥80% overall, ≥90% for FIFOCalculator.

Design system components tested in `MarginDesignSystemTests.swift` with logic extensions for testability.

---

## 16. File Reference

| File | Purpose |
|---|---|
| `DesignSystem/Theme.swift` | Colors, radii, spacing, Double formatting extensions |
| `DesignSystem/GlassCard.swift` | Glass container ViewModifier |
| `DesignSystem/PnLLabel.swift` | Colored P&L text with arrow |
| `DesignSystem/MetricCard.swift` | Single KPI glass card |
| `DesignSystem/TradeRowView.swift` | Trade list row |
| `DesignSystem/TradingModeBadge.swift` | Spot/Cross/Isolated margin pill badge |
| `DesignSystem/MarginPnLLabel.swift` | P&L with borrowing fee subtitle |
| `DesignSystem/MarginHoldingRow.swift` | Holding row with margin columns |
| `EasyCryptoApp.swift` | App entry, ModelContainer, background tasks |
| `ContentView.swift` | TabView shell, onboarding gate |
