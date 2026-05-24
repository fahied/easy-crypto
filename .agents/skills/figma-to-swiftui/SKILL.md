---
name: figma-to-swiftui
description: "Convert Figma core components and foundation tokens to SwiftUI code for the Emirates DesignSystem package. Use when: given a Figma link, Figma node ID, or component name to implement as SwiftUI. Produces deterministic DS-prefixed components with previews, token mappings, and Companion demo views."
argument-hint: "Figma component link or node name, e.g. 'Button' or a Figma URL"
---

# Figma → SwiftUI Conversion

Convert Figma design system components into production-ready SwiftUI code that matches the exact conventions of the Emirates DesignSystem Swift package.

## When to Use
- Given a Figma link to a **whole screen/frame** — scans all core components on that screen, identifies which already exist in the repo, and only implements the missing ones
- Given a Figma link to a **single core component** or foundation token
- Asked to implement a new DS component from a Figma design
- Asked to add variants/states to an existing DS component
- Migrating Figma design token changes into Swift code

## Procedure

### Phase 0: Screen-Level Audit (when a full screen link is provided)

This phase is **critical** to avoid duplicating effort. Run it whenever the user provides a Figma link to a screen, page, or frame (not a single component).

#### Step 0a: Scan the Figma screen for all component instances

Using Figma MCP tools (or manual inspection):
1. Paste the screen/frame URL into the prompt so the MCP server can extract the `node-id`
2. Run `get_metadata` on the selection — returns an XML representation of all layers with IDs, names, types, positions, and sizes. This is efficient for large screens and gives the full node map
3. Run `get_screenshot` for a visual reference of the screen layout
4. From the metadata XML, identify all **component instance** nodes (look for component names in layer names/types)
5. Deduplicate by component name — each unique component is a candidate
6. For each unique component, run `search_design_system` with the component name to check if it exists in the connected Figma libraries
7. Run `get_variable_defs` on the selection to extract all tokens (colors, spacing, typography) used across the screen

For specific components that need deeper inspection:
8. Run `get_design_context` on individual component nodes — prompt it for **iOS SwiftUI** output (default is React + Tailwind)
   - Example prompt: "Generate my Figma selection in iOS SwiftUI"
   - If the full-screen context is too large/truncated, use `get_metadata` first, then `get_design_context` on smaller sections

**If Figma MCP is unavailable**, ask the user:
> "List all the distinct DS components visible on this screen (e.g., Button, Badge, Card, HeroBanner, etc.) — or share a screenshot and I'll identify them."

#### Step 0b: Cross-reference each component against the existing repo

For each unique component name found on the screen:

1. **Normalize the name** to the DS convention: strip spaces, apply `DS` prefix, PascalCase
   - Figma "Image Card" → search for `DSImageCard`
   - Figma "Basic Button" → search for `DSBasicButton`
   - Figma "Badge" → search for `DSBadge`

2. **Search the repo** for existing implementations:
   ```
   Search: DesignSystem/CoreComponents/**/ for files matching DS<NormalizedName>*.swift
   Also search: public struct DS<NormalizedName> in *.swift files
   ```

3. **Classify each component** into one of three buckets:

   | Status | Meaning | Action |
   |---|---|---|
   | **EXISTS** | `DS<Name>.swift` found with matching variants/states | Reuse as-is — no work needed |
   | **PARTIAL** | `DS<Name>.swift` found but missing variants/states shown on screen | Extend the existing component (add new enum cases, styles) |
   | **MISSING** | No matching `DS<Name>` found in `CoreComponents/` | Implement from scratch using Phase 1–3 |

4. **Also check foundation tokens**: For any new color, spacing, or typography token visible on the screen, search `UIFoundation/` for existing tokens before creating new ones.

#### Step 0c: Present the audit report

Before writing any code, output a summary table:

```
## Screen Audit: <Screen Name>

| # | Figma Component | DS Component | Status | Action |
|---|---|---|---|---|
| 1 | Basic Button (primary) | DSBasicButton | EXISTS | Reuse |
| 2 | Badge (alert, positive) | DSBadge | EXISTS | Reuse |
| 3 | Trip Hero Banner | DSTripHeroBanner | EXISTS | Reuse |
| 4 | Rating Stars | — | MISSING | Implement |
| 5 | Fare Breakdown Card | — | MISSING | Implement |
| 6 | Chip (with new "selected" state) | DSChip | PARTIAL | Extend |

**Existing (reuse):** 3 components
**Partial (extend):** 1 component
**Missing (implement):** 2 components
```

**Wait for user confirmation** before proceeding to implementation. The user may deprioritize some components or adjust scope.

#### Step 0d: Execute in dependency order

Once confirmed, implement only MISSING and PARTIAL components:
1. Sort by dependency — if Component A uses Component B, implement B first
2. Foundation tokens first (colors, spacing, typography needed by missing components)
3. Then components, one at a time, each going through Phase 1 → Phase 2 → Phase 3
4. Skip Phase 1 Figma inspection for EXISTS components entirely

---

### Phase 1: Figma Inspection (per component)

Follow the detailed extraction guide in `./references/figma-inspection.md`. **Skip this phase for components classified as EXISTS in the Screen Audit.**

#### Required Figma MCP flow (do not skip steps):

1. **`get_design_context`** — Fetch the structured design representation for the component node. Prompt for iOS SwiftUI output:
   - "Generate my Figma selection in iOS. Use components from DesignSystem/CoreComponents"
   - This returns layout, colors, typography, spacing as structured data
   - If the response is too large or truncated, run `get_metadata` first to get the high-level node map, then re-fetch only the specific sub-nodes with `get_design_context`

2. **`get_screenshot`** — Get a visual reference of the component variant being implemented. Use this to validate your implementation matches the design 1:1

3. **`get_variable_defs`** — Extract all variables and styles (colors, spacing, typography tokens) used in the component. This provides the exact Figma token names to map to DS tokens

4. **`get_code_connect_map`** — Check if this component already has Code Connect mappings to existing Swift code in the repo

5. **`search_design_system`** — Search connected libraries for sub-components referenced by this component (e.g., if a Card uses a Badge, search for the Badge component)

6. If Figma MCP is unavailable, ask the user for the required information per the manual fallback checklist in `./references/figma-inspection.md`

#### Identify from inspection:
- Component name and all variant names (e.g., primary/secondary/tertiary)
- All states (enabled, disabled, pending, skeleton, pressed, etc.)
- All size variants (large, regular, small, etc.)
- Properties: text labels, icons, images, actions, optional slots
- Token usage: colors (background, text, border), spacing, radius, shadow, typography
- Layout direction, spacing, padding, alignment, frame constraints (see auto-layout mapping table)
- Interactive behavior: taps, toggles, selection, carousel

7. **Cross-reference with existing tokens** in `./references/token-map.md` to identify reusable tokens vs. tokens that need creation.

### Phase 2: Code Generation

Follow the strict patterns defined in `./references/component-patterns.md` and `./references/token-patterns.md`.

#### Step 1: Create Foundation Tokens (if needed)

If the Figma component uses tokens not yet in the codebase:
- **Colors**: Add to `DSColor+Semantic.swift` or appropriate extension following [token patterns](./references/token-patterns.md)
- **Spacing**: Already comprehensive — only add if a new scale value is introduced
- **Rounding**: Add case to `DSRounding` enum if new radius needed
- **Shadow**: Add case to `DSShadow` enum if new shadow profile needed
- **Typography**: Add to `Font+DSFont.swift` extension if new text style needed

#### Step 2: Create the Component

Generate files in `DesignSystem/CoreComponents/<ComponentName>/`:

1. **Main component file** (`DS<ComponentName>.swift`):
   - Follow exact struct pattern from `./references/component-patterns.md`
   - Include Figma link in file header comment
   - Declare all enums for variants/states/types as `public enum` with `CaseIterable` where applicable
   - Use `public struct DS<Name>: View` (add `Sendable` for simple components)
   - All properties as `public let` (use `@Binding` only for parent-controlled state)
   - `public init(...)` with sensible defaults
   - `public var body: some View` implementation
   - Private helper computed properties and `@ViewBuilder` methods
   - `#Preview` blocks covering all major states/variants

2. **Style files** (if ButtonStyle or custom styling needed):
   - `DS<ComponentName><Variant>Style.swift` implementing `ButtonStyle`
   - Use `AnyButtonStyle` wrapper for type-erased style switching

3. **Sub-component files** (for complex components):
   - Break into logical sub-views in the same folder
   - Each sub-view follows the same DS-prefix naming

#### Step 3: Create Previews

Every component MUST have `#Preview` blocks that:
- Show **all variant × state combinations** (use nested `ForEach` with `CaseIterable`)
- Use `traits: .modifier(PreviewFontRegistration())` for custom fonts
- Use realistic sample data (not "Lorem ipsum")
- Do NOT use `@State` property wrapper directly in previews
  - Exception: When `@Binding` is required, wrap in a `PreviewState: View` struct
- Name previews descriptively: `#Preview("DSBadge")`, `#Preview("DSBasicButton - Regular")`

#### Step 4: Create Companion Demo View (if applicable)

Generate demo view in `Companion/Companion/Components/<Category>/Components/<Name>View.swift`:
- Use `@State` properties for interactive picker controls
- Use `ControlsCard { ... }` wrapper for settings
- Use `ToggleControl(title:isOn:)` for boolean toggles
- Use `Picker` with `.pickerStyle(.menu)` or `.segmented`
- End with `.withToolbar(name: "<Component Name>")`
- Add simple `#Preview` block

#### Step 5: Build Verification

Run the build command to verify:
```bash
xcodebuild -scheme DesignSystem clean build test \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4'
```

### Phase 3: Validation Checklist

Before marking the component complete, verify all items from `./references/checklist.md`.

### Phase 4: Post-Implementation (Figma MCP)

After code is generated and builds successfully:

1. **Visual validation** — Run `get_screenshot` on the original Figma selection and compare against the SwiftUI preview. Strive for 1:1 visual parity. When conflicts arise, prefer DS tokens and adjust spacing minimally to match visuals

2. **Code Connect** — Use `add_code_connect_map` to create mappings between the Figma component nodes and their new Swift implementations. This ensures developers can see the code reference directly in Figma's Dev Mode:
   ```
   add_code_connect_map({
     nodeId: "<figma_node_id>",
     codeConnectSrc: "DesignSystem/CoreComponents/<Name>/DS<Name>.swift",
     codeConnectName: "DS<Name>"
   })
   ```

3. **Design system rules** — If this is the first time setting up the workspace, run `figma-create-design-system-rules` to generate a rules file that teaches the agent the project's DS conventions. This only needs to be done once per project

## Figma MCP Asset Handling Rules

- If the Figma MCP server returns a **localhost source** for an image or SVG, use that source directly
- Do NOT import new icon packages — all assets should come from the Figma payload or existing `DSIcon` constants
- Do NOT create placeholders if a localhost source is provided
- Treat the `get_design_context` output (default React + Tailwind) as a **representation of design and behavior**, not as final code style — translate into this project's SwiftUI + DSToken conventions

## Key Rules

### MUST follow:
- `DS` prefix on all public design system types
- `public` access on all types, properties, and inits
- `import UIFoundation` in CoreComponents files
- `.dsSpacingN` for ALL spacing (never hardcoded except in token definitions)
- `DSColor.semanticName` for ALL colors
- `.cornerRadius(.regular)` etc. using `DSRounding` enum
- `.font(.dsBodyBase)` etc. using `Font` extensions
- `Sendable` conformance where thread safety is needed
- Figma link in comment header of every component file
- Support dark mode, RTL, and VoiceOver accessibility

### MUST NOT:
- Create new types when Swift/SwiftUI natives suffice
- Use `@State` directly in `#Preview` blocks (wrap in struct if `@Binding` needed)
- Leave TODO comments — complete the implementation
- Use hardcoded color values — always use DSColor tokens
- Use hardcoded spacing — always use .dsSpacingN
- Use `foregroundColor()` — use `foregroundStyle()` instead

## References

- `./references/figma-inspection.md` — Detailed Figma MCP extraction guide and manual fallback checklist
- `./references/component-patterns.md` — Exact patterns for struct declaration, init, body, enums, styles
- `./references/token-patterns.md` — Token declaration patterns for colors, spacing, fonts, shadows, rounding
- `./references/checklist.md` — Completion checklist for every component
- `./references/token-map.md` — Figma token name → Swift token mapping table
