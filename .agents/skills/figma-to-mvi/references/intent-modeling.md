# Intent Modeling Reference

Rules and patterns for defining MVI intents from Figma interactions.

## Intent Naming Conventions

### Semantic names — not UI events

| Bad (UI event) | Good (semantic intent) |
|---|---|
| `onButtonTap` | `SubmitBooking` |
| `onTextChange` | `UpdateSearchQuery` |
| `onSwipe` | `DismissNotification` |
| `onPullDown` | `RefreshTripList` |
| `onScroll` | `LoadMoreFlights` |
| `onToggle` | `ToggleMuteNotifications` |
| `onBack` | `NavigateBack` |
| `onCellTap` | `SelectTrip` |

### Naming pattern

```
<Verb><Noun>[<Qualifier>]
```

Examples:
- `LoadTrips` — fetch trip list
- `SelectFlight` — choose a specific flight
- `SubmitPayment` — confirm payment action
- `DismissError` — clear error state
- `ToggleFavorite` — flip a boolean preference
- `UpdatePassengerName` — change a form field
- `RetryBooking` — re-attempt a failed action

## Intent Categories

### 1. Data Intents
Actions that fetch, create, update, or delete data.

```
Intent: LoadTrips
  Trigger: system (on screen appear)
  Parameters: none
  Description: Fetch the user's trip list from the API

Intent: RefreshTrips
  Trigger: user (pull-to-refresh)
  Parameters: none
  Description: Force-refresh the trip list

Intent: LoadMoreTrips
  Trigger: system (pagination threshold reached)
  Parameters: cursor: String
  Description: Load the next page of trips
```

### 2. Navigation Intents
Actions that change the visible screen or modal.

```
Intent: SelectTrip
  Trigger: user (tap on trip card)
  Parameters: tripId: String
  Description: Navigate to trip detail screen

Intent: NavigateBack
  Trigger: user (back button / swipe)
  Parameters: none
  Description: Return to previous screen

Intent: OpenFilter
  Trigger: user (tap filter button)
  Parameters: none
  Description: Present the filter modal
```

### 3. Mutation Intents
Actions that modify local or remote state.

```
Intent: ToggleMuteNotifications
  Trigger: user (tap mute button)
  Parameters: tripId: String, isMuted: Bool
  Description: Toggle mute state for trip notifications

Intent: UpdatePassengerName
  Trigger: user (text input)
  Parameters: passengerId: String, name: String
  Description: Update passenger name in booking form
```

### 4. System Intents
Actions triggered by the system, not the user.

```
Intent: ScreenAppeared
  Trigger: system (lifecycle)
  Parameters: none
  Description: Screen became visible — trigger initial data load

Intent: PushNotificationReceived
  Trigger: system (push)
  Parameters: payload: NotificationPayload
  Description: Handle incoming push notification

Intent: ConnectivityChanged
  Trigger: system (network)
  Parameters: isConnected: Bool
  Description: Network connectivity status changed

Intent: TimerTick
  Trigger: system (timer)
  Parameters: none
  Description: Periodic refresh tick (e.g., countdown, auto-refresh)
```

### 5. Error Recovery Intents
Actions that respond to failures.

```
Intent: RetryLoad
  Trigger: user (tap retry button)
  Parameters: none
  Description: Retry the last failed data load

Intent: DismissError
  Trigger: user (tap dismiss / auto-timeout)
  Parameters: none
  Description: Clear the current error state
```

## Extraction from Figma

### Interactive element → Intent mapping

| Figma Element | Intent Pattern |
|---|---|
| Button with CTA text | `<Verb from CTA><Context>` — e.g., "Book Now" → `StartBooking` |
| Text input field | `Update<FieldName>` — e.g., name field → `UpdateName` |
| Toggle / switch | `Toggle<Feature>` — e.g., notifications toggle → `ToggleNotifications` |
| Dropdown / picker | `Select<Option>` — e.g., class picker → `SelectCabinClass` |
| List item tap | `Select<Entity>` — e.g., trip card → `SelectTrip` |
| Swipe action | `<SwipeAction><Entity>` — e.g., swipe to delete → `DeleteNotification` |
| Pull-to-refresh | `Refresh<DataSet>` |
| Scroll to bottom | `LoadMore<DataSet>` |
| Back button / gesture | `NavigateBack` |
| Tab bar item | `SwitchTab` with `tab: TabType` parameter |
| Search field | `UpdateSearchQuery` + `SubmitSearch` |
| Close / dismiss button | `Dismiss<Modal/Sheet>` |

### State indicators → System intents

| Figma State | Implied System Intent |
|---|---|
| Loading spinner on screen appear | `ScreenAppeared` → triggers `LoadData` |
| Skeleton view | `ScreenAppeared` → triggers `LoadData` (with skeleton placeholder) |
| Empty state with retry | `RetryLoad` intent exists |
| Error state with retry | `RetryLoad` + `DismissError` intents exist |
| Auto-updating timer / countdown | `TimerTick` system intent |
| Real-time status badge | `StatusUpdate` via WebSocket/push |

## Atomicity Rules

1. **One intent = one logical action**: Don't combine "select trip AND load flights" into one intent. Use `SelectTrip` which triggers `LoadFlights` as a side effect.
2. **Parameterize, don't duplicate**: Don't create `SelectTrip1`, `SelectTrip2`. Use `SelectTrip(tripId: String)`.
3. **Separate user from system**: Even if the result is the same (loading data), distinguish `RefreshTrips` (user pull-to-refresh) from `AutoRefreshTrips` (system timer) — they may have different side effects (analytics, loading indicators).

## Deduplication Rules

When the same logical action appears on multiple screens:

1. If the intent has **identical behavior** on both screens → define it once, reference from both
2. If the intent has **different behavior** per screen → create screen-specific variants: `LoadHomeTrips` vs `LoadSearchTrips`
3. Shared intents belong in a **global intents** section; screen-specific intents belong under their screen
