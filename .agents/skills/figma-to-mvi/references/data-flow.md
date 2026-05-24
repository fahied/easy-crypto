# Data Flow Reference

Rules and patterns for mapping data sources and defining data flow in MVI architecture.

## Data Source Types

### 1. REST API
Standard request-response calls.

```
Source: REST API
  Method: GET /api/trips
  Trigger: on-demand (user action or screen appear)
  Update frequency: per-request
  Freshness: stale after fetch (must re-fetch for updates)
  Error mode: HTTP status codes → map to ErrorState
```

### 2. WebSocket / Server-Sent Events
Real-time push channels.

```
Source: WebSocket
  Channel: ws://api/notifications
  Trigger: persistent connection (open on screen appear, close on disappear)
  Update frequency: real-time (server-pushed)
  Freshness: always current while connected
  Error mode: connection drop → reconnect with backoff
```

### 3. Local Storage
Persisted data on device.

```
Source: Local DB (Core Data / SwiftData / SQLite)
  Trigger: on-demand read
  Update frequency: on-change (write-through from API responses)
  Freshness: depends on sync strategy
  Error mode: migration failures, corruption → fallback to API
```

### 4. In-Memory Cache
Transient data that lives only for the session.

```
Source: In-memory
  Trigger: computed or cached from API response
  Update frequency: per-session
  Freshness: valid until app termination or explicit invalidation
  Error mode: none (reconstructed on cache miss)
```

### 5. Computed / Derived
Fields calculated from other state.

```
Source: Computed
  Derivation: <formula or description>
  Dependencies: <list of source fields>
  Update frequency: on dependency change
  Error mode: none
```

### 6. User Input
Data entered by the user in the current session.

```
Source: User input
  Element: text field / picker / toggle
  Trigger: on-change (keystrokes, selection)
  Persistence: form state in memory (optionally draft-saved to disk)
  Validation: <rules>
```

## Data Source Identification from Figma

### Heuristics for determining source

| Figma Clue | Likely Source |
|---|---|
| Data varies per user (name, bookings, miles) | REST API (authenticated) |
| Data is static across users (T&C, FAQ) | REST API (cacheable) or bundled |
| Real-time counter or status badge | WebSocket or polling |
| Data that persists across app launches (settings, preferences) | Local storage |
| Data that changes while screen is visible (live flight status) | WebSocket / SSE |
| Data shown immediately on app launch (cached trips) | Local DB → API refresh |
| Form field with user typing | User input |
| Derived labels ("3 items", "Total: $450") | Computed |
| Countdown timer | Local timer + initial value from API |

### Screen-level data flow pattern

For each screen, map the complete flow:

```
Screen: TripList

Flow:
1. ScreenAppeared intent fires
2. Processor checks local DB for cached trips
3. If cache hit → emit state with cached trips (isLoading = false)
4. Processor calls GET /api/trips
5. On response → update local DB + emit state with fresh trips
6. If cache miss → emit state with isLoading = true, wait for API

Data sources:
  trips         → Local DB (cache) + REST API (source of truth)
  unreadCount   → computed from notifications state
  userName      → Local DB (from login session)
```

## Data Flow Patterns

### Pattern 1: API-first (no cache)
Simplest pattern. Fetch on every screen appear.

```
Intent → Processor → API call → State update
```

Use when:
- Data changes frequently
- Freshness is critical
- Payload is small

### Pattern 2: Cache-then-network
Show cached data immediately, then refresh from API.

```
Intent → Processor → Read cache → State (cached) → API call → State (fresh) → Write cache
```

Use when:
- Screen should load instantly
- Stale data is acceptable briefly
- Good for lists the user visits repeatedly

### Pattern 3: Network-then-cache
Fetch from API, cache for offline.

```
Intent → Processor → API call → State (fresh) → Write cache
                        ↓ (on failure)
              Read cache → State (stale, with offline banner)
```

Use when:
- Fresh data is preferred
- Offline fallback is needed
- Cache is a safety net, not primary

### Pattern 4: Real-time stream
Persistent connection with live updates.

```
Intent (connect) → Processor → Open WebSocket → On each message → State update
Intent (disconnect) → Processor → Close WebSocket
```

Use when:
- Data changes in real-time (flight status, chat, live scores)
- Server pushes updates

### Pattern 5: Optimistic update
Update UI immediately, confirm with API.

```
Intent → Processor → State (optimistic) → API call
                          ↓ (on failure)
                     State (rollback)
```

Use when:
- Action is low-risk (toggle favorite, mark read)
- Instant feedback improves UX
- Rollback is acceptable on failure

### Pattern 6: Form submission
Collect input, validate, submit.

```
UpdateField intents → State (form fields updated)
SubmitForm intent → Processor → Validate → API call → Success state | Error state
```

Use when:
- Multi-field forms
- Client-side validation before submission

## Data Flow Diagram Template

Use this template for each feature/screen:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Sources    │     │  Processor   │     │    State     │
├─────────────┤     ├──────────────┤     ├─────────────┤
│ REST API    │────▶│              │────▶│ data fields  │
│ WebSocket   │────▶│ Intent       │     │ loading      │
│ Local DB    │────▶│ Handler      │     │ error        │
│ User Input  │────▶│              │     │ pagination   │
└─────────────┘     └──────┬───────┘     └──────┬──────┘
                           │                     │
                    ┌──────▼───────┐      ┌──────▼──────┐
                    │ Side Effects │      │    View     │
                    ├──────────────┤      │  (render)   │
                    │ API calls    │      └─────────────┘
                    │ Navigation   │
                    │ Analytics    │
                    │ Cache writes │
                    └──────────────┘
```

## API Contract Inference

When the backend API is not yet defined, infer a reasonable contract from the Figma data:

```
Inferred endpoint: GET /api/trips
Response shape:
  {
    "items": [Trip],
    "pagination": {
      "hasNext": Bool,
      "cursor": String?
    }
  }

Inferred endpoint: POST /api/bookings
Request body:
  {
    "tripId": String,
    "passengers": [Passenger],
    "paymentMethod": String
  }
Response shape:
  {
    "bookingId": String,
    "status": "confirmed" | "pending"
  }
```

Mark all inferred contracts clearly:
> ⚠️ **Inferred** — confirm with backend team before implementation.
