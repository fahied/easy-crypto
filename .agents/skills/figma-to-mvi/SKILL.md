---
name: figma-to-mvi
description: "Convert Figma screens and flows into a complete MVI (Model-View-Intent) architecture specification. Produces domain models, intents, state objects, data source mappings, persistence strategies, and side-effect definitions. No UI code generated."
argument-hint: "Figma screen link or flow description, e.g. 'Booking flow' or a Figma URL"
---

# Figma → MVI Architecture Specification

Convert Figma design screens and user flows into a production-grade MVI architecture specification. Outputs domain models, intents, state definitions, data flow mappings, and side-effect strategies.

## When to Use
- Given a Figma link to a **screen or flow** — extracts all data, interactions, and states to produce the full MVI spec
- Given a Figma link to a **single screen** — produces a scoped MVI spec for that screen
- Asked to define the architecture for a feature before implementation begins
- Asked to map a Figma prototype flow to backend contracts and state management

## Important Rules
- Do **NOT** generate UI code or visual components
- Focus only on architecture, data, and interaction modeling
- Be deterministic, structured, and exhaustive
- Assume production-grade scalability and maintainability
- Prefer explicit over implicit assumptions
- Avoid hallucinated features not implied by the design

## Procedure

### Phase 0: Screen & Flow Audit

Run this first to understand the full scope before modeling.

#### Step 0a: Scan the Figma screens

Using Figma MCP tools (or manual inspection):
1. Run `get_metadata` on the selection — returns XML of all layers with IDs, names, types, positions, sizes
2. Run `get_screenshot` for visual reference of each screen
3. From the metadata, identify:
   - All **data-displaying elements**: labels, lists, cards, forms, images, counts, badges, timers
   - All **interactive elements**: buttons, inputs, toggles, pickers, gestures, navigation triggers
   - All **state indicators**: loading spinners, empty states, error banners, skeleton views, disabled states
4. Run `get_variable_defs` to extract tokens — helps identify conditional styling tied to state variants

For user flows (multi-screen):
5. Run `get_metadata` on each screen in the flow
6. Identify transition points between screens (navigation triggers)
7. Map the flow order and branching paths

**If Figma MCP is unavailable**, ask the user:
> "List all screens in this flow, the data shown on each, and all interactive elements — or share screenshots and I'll identify them."

#### Step 0b: Catalog all elements

For each screen, produce a raw inventory:

```
## Screen: <Screen Name>

### Data Elements
- [element] → inferred field / entity
- [element] → inferred field / entity

### Interactive Elements
- [element] → inferred intent
- [element] → inferred intent

### State Indicators
- [indicator] → inferred state
```

#### Step 0c: Present scope summary

Before modeling, output a summary table:

```
## Flow Audit: <Flow Name>

| # | Screen | Data Entities | Intents | States |
|---|--------|--------------|---------|--------|
| 1 | Home   | 3            | 5       | 4      |
| 2 | Detail | 2            | 3       | 3      |
| 3 | Confirm| 1            | 2       | 3      |

**Total screens:** 3
**Total entities:** 4 (deduplicated)
**Total intents:** 10
**Cross-screen dependencies:** 2
```

**Wait for user confirmation** before proceeding to the full specification.

---

### Phase 1: Domain & Data Modeling

Follow the detailed guide in `./references/domain-modeling.md`.

**Goal:** Identify all data required to render the screen(s).

#### Steps:
1. Extract all UI elements that display data (from Phase 0 inventory)
2. Infer domain entities from labels, lists, cards, forms, and states
3. Normalize into reusable models — merge duplicate concepts across screens
4. Define relationships between entities

#### Output format per entity:

```
Entity: <Name>
Fields:
  - fieldName: Type (required|optional) — source: <API|computed|local>
Relationships:
  - hasMany: <OtherEntity>
  - belongsTo: <OtherEntity>
Computed:
  - derivedField: description of computation
```

#### Constraints:
- Avoid UI-specific naming (~~CardModel~~) → prefer domain naming (`Trip`, `Booking`, `Flight`)
- Merge duplicate concepts across screens
- Mark optional vs required fields explicitly
- Identify pagination / list structures if present

---

### Phase 2: Intent Modeling

Follow the detailed guide in `./references/intent-modeling.md`.

**Goal:** Define all possible user and system intents.

#### Steps:
1. Identify all user interactions: taps, inputs, gestures, navigation, selections, swipes
2. Identify system-triggered actions: lifecycle events, auto-refresh, timers, push notifications, background updates
3. Group by screen, then deduplicate cross-screen intents

#### Output format per intent:

```
Intent: <SemanticName>
  Screen: <ScreenName>
  Trigger: user | system
  Parameters: <param: Type, ...> | none
  Description: <what this intent represents>
```

#### Constraints:
- Intents must be **atomic** and **composable**
- Use **semantic** names, not UI event names:
  - ~~`onButtonTap`~~ → `SubmitBooking`
  - ~~`onTextChange`~~ → `UpdateSearchQuery`
  - ~~`onSwipe`~~ → `DismissNotification`
- Group navigation intents separately from data intents

---

### Phase 3: State Modeling

Follow the detailed guide in `./references/state-modeling.md`.

**Goal:** Define all possible UI states derived from intents.

#### Steps:
1. For each screen, identify: loading, success, empty, error, partial states
2. Map how each intent transforms state
3. Define the single source of truth state object

#### Output format:

```
State: <ScreenName>State
  Fields:
    - fieldName: Type — default: <value>
  Sub-states:
    - nestedState: <SubState>

Transitions:
  Intent              → State Change
  -------------------------------------------
  LoadData            → isLoading = true
  LoadDataSuccess     → isLoading = false, items = payload
  LoadDataFailure     → isLoading = false, error = message
```

#### Constraints:
- Follow **unidirectional data flow**: Intent → Processor → State → View
- State must be **serializable** (no closures, no view references)
- No side-effects inside state definitions
- Exhaustive — every intent must map to a state transition

---

### Phase 4: Data Source & Flow Mapping

Follow the detailed guide in `./references/data-flow.md`.

**Goal:** Define where each piece of data originates from.

#### Steps:
1. For each entity field, identify the source
2. Map the full data flow from source to state

#### Output — Data source table:

```
| Field              | Source      | Update Frequency | Caching  |
|--------------------|------------|-----------------|----------|
| trip.name          | REST API   | on-demand       | local DB |
| trip.status        | WebSocket  | real-time       | memory   |
| unreadCount        | computed   | derived         | none     |
| user.preferences   | local      | on-change       | disk     |
```

#### Output — Data flow:

```
Source (API / WebSocket / Local)
  → Repository / DataSource
    → Processor (intent handler)
      → State (single source of truth)
        → View (render)
```

---

### Phase 5: Persistence Strategy

**Goal:** Define how data is stored and cached.

#### Output:

```
| Entity       | Persistence     | TTL / Invalidation       | Offline Support |
|-------------|----------------|-------------------------|-----------------|
| Trip         | local DB        | invalidate on push       | read-only       |
| User         | local DB        | 24h TTL                  | full            |
| SearchResult | in-memory       | cleared on new search    | none            |
| Media        | disk cache      | LRU, 100MB cap          | cached items    |
```

Include:
- Cache invalidation rules per entity
- Offline support strategy (full / read-only / none)
- Sync strategy for offline mutations (queue / discard / conflict resolution)

---

### Phase 6: Side Effects & Processing

**Goal:** Define how intents are processed and what side effects they trigger.

#### Output format per intent:

```
Intent: SubmitBooking
  Processing:
    1. Validate form state
    2. Call POST /bookings API
    3. On success → emit BookingConfirmed state
    4. On failure → emit BookingError state
  Side Effects:
    - API: POST /bookings
    - Analytics: track("booking_submitted", { tripId })
    - Navigation: push → ConfirmationScreen
  Error Handling:
    - Network error → retry with exponential backoff (max 3)
    - Validation error → inline field errors in state
    - Server error → generic error banner
```

Include:
- Intent handler logic (high-level, not code)
- Side effects: API calls, navigation, analytics, logging
- Error handling strategy per intent category
- Retry / timeout policies

---

### Phase 7: Assumptions & Gaps

**Goal:** Surface all unknowns explicitly.

#### Output:

```
## Assumptions
- [ ] <assumption made due to ambiguous design>
- [ ] <assumption about backend contract>

## Open Questions
- [ ] <question requiring product/design clarification>
- [ ] <question requiring backend team input>

## Risks
- [ ] <potential issue if assumption is wrong>
```

---

### Phase 8: Cross-Screen Dependencies (when flow is provided)

**Goal:** Map how state flows between screens in a multi-screen journey.

#### Output — Navigation intent map:

```
| From Screen | Intent           | To Screen    | Passed State           |
|-------------|-----------------|-------------|----------------------|
| Home        | SelectTrip       | TripDetail   | tripId               |
| TripDetail  | StartBooking     | BookingForm  | trip, selectedFlight |
| BookingForm | SubmitBooking    | Confirmation | bookingResult        |
| Confirmation| ReturnHome       | Home         | (clear booking state)|
```

#### Output — Shared state:

```
- UserSession: available across all screens (global scope)
- SelectedTrip: shared between TripDetail ↔ BookingForm (flow scope)
```

---

## Final Deliverable

A single structured specification document containing:

1. **Flow Audit** — scope summary table
2. **Domain Models** — all entities with fields, types, relationships
3. **Intents** — grouped by screen, with trigger / params / description
4. **State Definitions** — state objects with transition maps
5. **Data Source Mapping** — field → source → frequency table
6. **Persistence Strategy** — caching, offline, invalidation rules
7. **Side Effects** — processing logic, API calls, analytics, navigation, error handling
8. **Assumptions & Gaps** — explicit unknowns and open questions
9. **Navigation Map** — cross-screen state dependencies (if multi-screen flow)

## Quality Bar
- Output must be consistent with real-world production apps
- Avoid hallucinated features not implied by design
- Prefer explicit over implicit assumptions
- Use clear, domain-appropriate naming conventions
- Every intent must have a corresponding state transition
- Every data field must have an identified source
- No orphaned states (every state must be reachable via an intent)

## Figma MCP Usage
- `get_metadata` — structural analysis (layer hierarchy, component instances)
- `get_screenshot` — visual reference only; do not infer pixel-level details
- `get_variable_defs` — identify conditional styling that implies state variants
- `get_design_context` — prompt for architecture analysis: *"Analyze the data, interactions, and states in this Figma selection"*
- Do **NOT** use Figma MCP to generate code — this skill produces specifications only

## References

- `./references/domain-modeling.md` — Entity extraction patterns and normalization rules
- `./references/intent-modeling.md` — Intent naming conventions and categorization guide
- `./references/state-modeling.md` — State object patterns and transition mapping
- `./references/data-flow.md` — Data source identification and flow mapping
- `./references/checklist.md` — Completion checklist for every MVI specification
