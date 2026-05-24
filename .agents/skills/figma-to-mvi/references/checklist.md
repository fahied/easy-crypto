# MVI Specification Completion Checklist

Verify every item before marking a specification as done.

## Phase 0: Screen & Flow Audit
- [ ] All screens in the flow identified and listed
- [ ] Each screen has a data element inventory
- [ ] Each screen has an interactive element inventory
- [ ] Each screen has a state indicator inventory
- [ ] Scope summary table presented with entity/intent/state counts
- [ ] User confirmed scope before proceeding

## Phase 1: Domain & Data Modeling
- [ ] All data-displaying UI elements mapped to entity fields
- [ ] Entities use domain naming (not UI naming)
- [ ] Duplicate entities across screens deduplicated
- [ ] Relationships defined (one-to-one, one-to-many, many-to-many)
- [ ] Computed fields identified and derivation described
- [ ] Optional vs required marked on every field
- [ ] Pagination structures defined for scrollable lists
- [ ] Enums extracted for finite variant sets
- [ ] No orphaned fields (every field is displayed somewhere or used in computation)

## Phase 2: Intent Modeling
- [ ] All user interactions mapped to intents
- [ ] All system-triggered actions mapped to intents
- [ ] Intent names are semantic (not UI event names)
- [ ] Every intent has: name, screen, trigger source, parameters, description
- [ ] Intents are atomic (one logical action each)
- [ ] Intents are parameterized (no duplicates for different entities)
- [ ] Navigation intents separated from data intents
- [ ] Cross-screen intents deduplicated
- [ ] Error recovery intents defined (retry, dismiss)

## Phase 3: State Modeling
- [ ] One state object per screen defined
- [ ] All data fields present with types and defaults
- [ ] Loading states separated (initial, refresh, pagination, submission)
- [ ] Error state defined with type, message, retry info
- [ ] Pagination fields defined
- [ ] UI control fields defined (selected tab, sheet visibility, etc.)
- [ ] Computed fields identified (not stored, derived)
- [ ] Sub-states used where sections load independently
- [ ] Every intent has a corresponding state transition
- [ ] State is serializable (no closures, views, publishers)
- [ ] No orphaned states (every state reachable via an intent)
- [ ] Unidirectional flow maintained (Intent → Processor → State → View)

## Phase 4: Data Source & Flow Mapping
- [ ] Every entity field has an identified source
- [ ] Source types classified (REST API, WebSocket, local, computed, user input)
- [ ] Update frequency defined per field
- [ ] Caching strategy noted per field
- [ ] Data flow diagram present (Source → Repository → Processor → State → View)
- [ ] API contracts inferred and marked as needing confirmation
- [ ] Real-time data sources identified (WebSocket, SSE, polling)

## Phase 5: Persistence Strategy
- [ ] Every entity has a persistence type (in-memory, local DB, disk cache)
- [ ] TTL / invalidation rules defined per entity
- [ ] Offline support strategy defined (full, read-only, none)
- [ ] Sync strategy for offline mutations defined (queue, discard, conflict resolution)
- [ ] Cache invalidation triggers identified (push, TTL, manual)

## Phase 6: Side Effects & Processing
- [ ] Every intent has processing steps described (high-level, not code)
- [ ] Side effects listed per intent: API calls, navigation, analytics, logging
- [ ] Error handling strategy defined per intent category
- [ ] Retry / timeout policies specified for network operations
- [ ] Analytics events mapped to intents
- [ ] Navigation side effects include target screen and passed state

## Phase 7: Assumptions & Gaps
- [ ] All assumptions listed and marked
- [ ] Open questions for product/design team listed
- [ ] Open questions for backend team listed
- [ ] Risks identified if assumptions are wrong
- [ ] No silent assumptions (everything explicit)

## Phase 8: Cross-Screen Dependencies (if flow)
- [ ] Navigation intent map complete (from → intent → to → passed state)
- [ ] Shared state identified with scope (global vs flow-scoped)
- [ ] State cleanup defined on flow exit (what gets cleared)
- [ ] Deep link entry points identified (if applicable)
- [ ] Back navigation state restoration defined

## Overall Quality
- [ ] No hallucinated features (everything traces back to a Figma element)
- [ ] No UI code generated (specification only)
- [ ] Consistent naming conventions throughout
- [ ] No orphaned intents (every intent has a trigger source)
- [ ] No orphaned entities (every entity is displayed or used)
- [ ] Explicit over implicit — no hidden assumptions
- [ ] Production-grade scalability considered (pagination, caching, error handling)
