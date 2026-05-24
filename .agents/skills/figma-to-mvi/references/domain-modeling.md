# Domain & Data Modeling Reference

Rules and patterns for extracting domain entities from Figma designs.

## Entity Extraction Rules

### 1. Identify data-bearing UI elements

Scan every screen for elements that **display** data:

| UI Element | Likely Entity / Field |
|---|---|
| Text label with a person's name | `User.name` or `Passenger.name` |
| Numeric badge / counter | `<Entity>.count` (computed or fetched) |
| List of cards | Collection of `<Entity>` |
| Date / time text | `<Entity>.date`, `<Entity>.departureTime` |
| Image / avatar | `<Entity>.imageURL` |
| Status pill / badge | `<Entity>.status` (enum) |
| Price / currency text | `<Entity>.price: Money` (amount + currency) |
| Toggle / checkbox | `<Entity>.isEnabled: Bool` |
| Progress bar | `<Entity>.progress: Double` (0.0–1.0) |
| Map pin / location | `<Entity>.location: Coordinate` |
| Star rating | `<Entity>.rating: Double` |

### 2. Naming conventions

| Rule | Example |
|---|---|
| Use **domain** nouns, not UI nouns | `Trip` not `TripCard` |
| Singular for entities | `Flight` not `Flights` |
| Plural only for collection fields | `trip.flights: [Flight]` |
| PascalCase for entity names | `BookingConfirmation` |
| camelCase for field names | `departureTime` |
| Prefix booleans with `is`/`has`/`can` | `isActive`, `hasNotification`, `canEdit` |

### 3. Normalization rules

- **Merge duplicates**: If the same data appears on multiple screens (e.g., trip name on Home and Detail), it is ONE entity — not two
- **Extract shared fields**: If two entities share 3+ fields, consider a common base or shared value type
- **Flatten shallow nesting**: If a "sub-entity" has only 1–2 fields, inline them as fields on the parent
- **Promote deep nesting**: If a group of fields appears in multiple entities, extract it as its own value type (e.g., `Address`, `Money`, `DateRange`)

### 4. Relationship patterns

```
One-to-One:   User → Profile         (user.profile)
One-to-Many:  Trip → [Flight]        (trip.flights)
Many-to-Many: Passenger ↔ Flight     (via BookingSegment)
Self-ref:     Comment → [Comment]    (comment.replies)
```

### 5. Computed fields

If a field can be **derived** from other fields, mark it as computed:

```
unreadCount = notifications.filter { !$0.isRead }.count   → computed
fullName = "\(firstName) \(lastName)"                      → computed
isOverdue = dueDate < Date.now                             → computed
totalPrice = items.reduce(0) { $0 + $1.price }            → computed
```

Computed fields have **no source** — they are derived from state.

### 6. Optional vs Required

- **Required**: The screen cannot render without this field (title, ID, primary content)
- **Optional**: The screen renders a fallback when absent (subtitle, image, secondary info)
- When in doubt, check the Figma design for empty/missing-data states — if an element disappears or shows a dash, the underlying field is optional

### 7. Pagination & Lists

When the Figma design shows a scrollable list:

```
Collection: <EntityName>List
  Items: [<Entity>]
  Pagination:
    strategy: cursor | offset | keyset
    pageSize: <inferred from visible items, typically 10-20>
    hasNextPage: Bool
    cursor: String? (for cursor-based)
    offset: Int (for offset-based)
  Loading:
    isLoadingInitial: Bool
    isLoadingMore: Bool
  Empty State:
    detected: yes|no (check if Figma shows an empty state variant)
```

### 8. Enum extraction

When the design shows a **finite set of visual variants** for a field:

```
Status badges: "Confirmed", "Pending", "Cancelled" → enum BookingStatus
Notification types: icon colors vary by type → enum NotificationType
Tab categories: fixed set of tabs → enum Category
```

Rules:
- If 2–7 variants → enum
- If 8+ variants or user-generated → String with known constants
- Always check if the enum already exists in the codebase before creating a new one
