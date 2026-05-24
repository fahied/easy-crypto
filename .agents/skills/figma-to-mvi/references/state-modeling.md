# State Modeling Reference

Rules and patterns for defining MVI state objects from Figma designs.

## Core Principle: Unidirectional Data Flow

```
User/System → Intent → Processor → State (new) → View (re-render)
                            ↓
                       Side Effects
                    (API, navigation, analytics)
```

State is **never mutated directly**. Every state change is the result of processing an intent.

## State Object Structure

### Single source of truth per screen

Each screen has exactly ONE state object that contains everything the view needs to render:

```
State: TripListState
  // Data
  trips: [Trip] = []
  selectedTripId: String? = nil

  // Loading
  isLoading: Bool = false
  isRefreshing: Bool = false
  isLoadingMore: Bool = false

  // Pagination
  hasNextPage: Bool = true
  cursor: String? = nil

  // Error
  error: ErrorState? = nil

  // UI hints (derived from data, not user input)
  isEmpty: Bool → computed (trips.isEmpty && !isLoading)
```

### Naming convention

```
<ScreenName>State
```

Examples: `TripListState`, `BookingFormState`, `NotificationCenterState`

## State Field Categories

### 1. Data fields
The actual domain data displayed on screen.

```
trips: [Trip]                    — list of domain entities
selectedTrip: Trip?              — currently selected entity
searchQuery: String              — user input preserved in state
formFields: BookingFormFields    — form state (nested value type)
```

### 2. Loading fields
Track async operation status. Use **separate booleans** for different loading contexts:

```
isLoading: Bool          — initial load (shows full-screen spinner/skeleton)
isRefreshing: Bool       — pull-to-refresh (shows refresh indicator)
isLoadingMore: Bool      — pagination (shows footer spinner)
isSubmitting: Bool       — form submission (shows button spinner)
```

Do NOT use a single `isLoading` for all contexts — the view needs to distinguish them.

### 3. Error fields
Errors as state, not exceptions:

```
error: ErrorState? = nil

ErrorState:
  message: String
  type: ErrorType (network | validation | server | unknown)
  retryIntent: Intent?    — which intent to fire on "Retry"
  dismissable: Bool       — can the user dismiss this error
```

### 4. Pagination fields

```
hasNextPage: Bool = true
cursor: String? = nil          — for cursor-based pagination
currentPage: Int = 0           — for offset-based pagination
totalCount: Int? = nil         — if the API provides it
```

### 5. UI control fields
Transient UI state that must survive recomposition:

```
selectedTabIndex: Int = 0
isFilterSheetPresented: Bool = false
expandedSectionIds: Set<String> = []
scrollPosition: String? = nil
```

### 6. Computed fields
Derived from other state fields — must not be stored, only computed:

```
isEmpty: Bool → trips.isEmpty && !isLoading
showEmptyState: Bool → isEmpty && error == nil
canSubmit: Bool → formFields.isValid && !isSubmitting
unreadCount: Int → notifications.filter { !$0.isRead }.count
```

## Sub-States (Nested State)

When a screen has logically independent sections, use nested state objects:

```
State: NotificationCenterState
  menu: MenuState              — tab selection, filter state
  list: NotificationListState  — items, pagination, loading
  detail: DetailState?         — expanded notification (nil when collapsed)

MenuState:
  selectedCategory: Category = .trips
  selectedFilter: String? = nil
  showFilters: Bool = false

NotificationListState:
  items: [Notification] = []
  isLoading: Bool = false
  hasNextPage: Bool = true
```

Rules for nesting:
- Nest when a section can **load independently** (e.g., list loads while tabs are static)
- Nest when a section has its **own error/loading** state
- Do NOT nest for simple grouping — only when it reduces complexity

## State Transition Mapping

Every intent MUST have a corresponding state transition:

```
## TripListState Transitions

Intent                  → State Change
------------------------------------------------------------
ScreenAppeared          → isLoading = true
LoadTripsSuccess        → isLoading = false, trips = payload, hasNextPage = ..., cursor = ...
LoadTripsFailure        → isLoading = false, error = ErrorState(...)
RefreshTrips            → isRefreshing = true
RefreshTripsSuccess     → isRefreshing = false, trips = payload (replace all)
RefreshTripsFailure     → isRefreshing = false, error = ErrorState(...)
LoadMoreTrips           → isLoadingMore = true
LoadMoreTripsSuccess    → isLoadingMore = false, trips += payload, cursor = ...
SelectTrip              → selectedTripId = tripId (+ navigation side effect)
DismissError            → error = nil
```

### Transition rules:

1. **Every intent produces exactly one state transition** (may update multiple fields simultaneously)
2. **Success/Failure always come in pairs** for async operations:
   - `LoadData` → `LoadDataSuccess` | `LoadDataFailure`
3. **Loading flags reset on both success AND failure**
4. **Error state is cleared explicitly** (via `DismissError`) or **implicitly** (on next successful load)
5. **Navigation intents may or may not change state** — some only trigger side effects

## State Serialization Rules

State must be serializable for:
- Debugging (log state snapshots)
- Testing (assert state equality)
- Restoration (save/restore on process death)

Therefore:
- ✅ Primitives: `String`, `Int`, `Bool`, `Double`
- ✅ Value types: `struct`, `enum`
- ✅ Collections: `Array`, `Set`, `Dictionary` (of serializable types)
- ✅ Optionals of the above
- ❌ Closures / functions
- ❌ View references
- ❌ Publishers / streams
- ❌ Mutable reference types (`class`)

## Extracting States from Figma

### Figma variants → State fields

| Figma Variant | State Representation |
|---|---|
| Screen with spinner overlay | `isLoading = true, trips = []` |
| Screen with content | `isLoading = false, trips = [...]` |
| Screen with "No results" | `isLoading = false, trips = [], isEmpty = true` |
| Screen with error banner | `error = ErrorState(...)` |
| Screen with skeleton cards | `isLoading = true` (view renders skeletons when loading + empty) |
| Button in disabled state | `canSubmit = false` (computed from form validity) |
| Pull-to-refresh indicator | `isRefreshing = true` |
| Bottom pagination spinner | `isLoadingMore = true` |

### Multiple Figma frames of same screen = state variants

If the Figma file shows the same screen in multiple frames (e.g., "Home - Loading", "Home - Empty", "Home - Error", "Home - Loaded"), each frame represents a **different state configuration** of the same state object. Map each frame to its field values.
