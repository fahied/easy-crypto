# Figma Inspection Guide

Detailed instructions for extracting design specifications from Figma, using the Figma MCP server tools when available and manual fallback when not.

> **Reference**: [Figma MCP skills](https://help.figma.com/hc/en-us/articles/39166810751895-Figma-skills-for-MCP) · [MCP server guide](https://github.com/figma/mcp-server-guide)

## Figma MCP Server — Available Tools

| Tool | Purpose |
|---|---|
| `get_design_context` | Structured design representation (layout, colors, typography). Default output is React + Tailwind — **prompt for iOS SwiftUI** |
| `get_metadata` | XML node map with layer IDs, names, types, positions, sizes. Efficient for large screens |
| `get_variable_defs` | Variables and styles used in selection (colors, spacing, typography tokens) |
| `get_screenshot` | Screenshot of selection for visual reference |
| `get_code_connect_map` | Mapping between Figma node IDs and code components in the repo |
| `search_design_system` | Search connected libraries for components, variables, and styles |
| `add_code_connect_map` | Create new mappings between Figma nodes and code components |
| `create_design_system_rules` | Generate rule files for consistent agent code output |

## Figma MCP — Available Skills (higher-level orchestration)

| Skill | Purpose |
|---|---|
| `figma-implement-design` | Turn a Figma design into working code — reads design, pulls assets, generates code |
| `figma-code-connect-components` | Connect published Figma components to matching code implementations |
| `figma-create-design-system-rules` | Analyze codebase and write rules for consistent DS code generation |

## Method 1: Figma MCP (Primary)

When Figma MCP tools are available, use them in this exact sequence.

### Step 1: Share the Figma URL

Paste the Figma URL into the prompt. The MCP server extracts the `node-id` automatically from:
```
https://www.figma.com/design/<fileKey>/<fileName>?node-id=<nodeId>
```

Example:
```
URL: https://www.figma.com/design/WtUfdvuiW8ZDDF66JdTYXx/App-%7C-Core-Components?node-id=149-19943
```

### Step 2: Get the node map (for screens/large selections)

```
get_metadata → XML representation of all layers
```

Use this **first** for full screens or large frames. It returns the complete layer tree efficiently so you can identify which sub-nodes to inspect in detail. Look for:
- **Component instance nodes**: identify all DS components used on the screen
- **Frame names**: understand the layout hierarchy
- **Layer types and names**: identify semantic groupings

### Step 3: Get the structured design context

```
get_design_context → structured representation (prompt for iOS SwiftUI)
```

Prompt: **"Generate my Figma selection in iOS SwiftUI. Use components from DesignSystem/CoreComponents"**

If the response is too large or truncated:
1. Use `get_metadata` to identify specific sub-nodes
2. Re-fetch only the needed sections with `get_design_context`

From the design context, extract:
- **Layout structure**: auto-layout direction, spacing, padding, alignment
- **Component instances**: nested components being reused
- **Text content**: typography styles, content, and alignment
- **Visual properties**: fills, strokes, corner radius, shadows, opacity

### Step 4: Get visual reference

```
get_screenshot → screenshot of the selection
```

Always get a screenshot to validate your implementation matches the Figma design 1:1 before marking complete.

### Step 5: Extract design tokens

```
get_variable_defs → variables and styles used in selection
```

Returns the exact Figma variable names for:
- Color tokens (fills, strokes, text colors)
- Spacing tokens (padding, gap)
- Typography tokens (font family, weight, size)
- Radius, shadow, and other style references

Map these to existing DS tokens using the token-map reference.

### Step 6: Check existing code connections

```
get_code_connect_map → existing Figma ↔ code mappings
```

Check if the component already has Code Connect mappings linking Figma nodes to Swift implementations. If it does, the component may already exist in the repo.

### Step 7: Search the design system library

```
search_design_system("Button") → matching components, variables, styles
```

Use for each sub-component referenced by the main component to:
- Find existing DS library components to reuse
- Identify standard variants/states already defined
- Avoid duplicating what's already in the connected libraries

### Step 8: Extract Variants (from design context)

From the `get_design_context` output, identify variant properties:
- `VARIANT` property type → Swift enum with cases
- `BOOLEAN` property type → optional Bool parameter
- `TEXT` property type → String parameter
- `INSTANCE_SWAP` property type → slot/content parameter (generic `some View`)

## Method 2: Manual Extraction (Fallback)

When Figma MCP is unavailable, ask the user for the following information:

### Required Information

1. **Component name**: What is the Figma component called?
2. **Screenshot**: Can you provide a screenshot of the component in Figma?
3. **Variants**: What variants/types does it have? (e.g., primary, secondary, tertiary)
4. **States**: What states does it support? (enabled, disabled, pressed, loading, skeleton)
5. **Size variants**: Any size options? (large, regular, small)

### Token Information

6. **Colors**: What background, text, and icon colors are used? (provide Figma token names or hex values)
7. **Spacing**: What padding and gap values are used? (provide px values)
8. **Typography**: What font styles are used? (heading level, body size, etc.)
9. **Corner radius**: What rounding is used? (4px, 8px, 12px, 16px, or full)
10. **Shadow**: Is any shadow applied? (describe or screenshot)

### Layout Information

11. **Layout direction**: Horizontal or vertical arrangement?
12. **Alignment**: Left, center, right? Top, center, bottom?
13. **Fixed dimensions**: Any fixed width/height constraints?
14. **Responsive behavior**: How does it scale? (fill width, hug content)

### Interactive Behavior

15. **Tap/click**: What happens on tap?
16. **Icons**: Any leading/trailing icons? Are they optional?
17. **Content slots**: Any customizable content areas?
18. **Animations**: Any transitions between states?

## Figma-to-Swift Auto-Layout Mapping

| Figma Property | SwiftUI Equivalent |
|---|---|
| Auto layout: Horizontal | `HStack(spacing:)` |
| Auto layout: Vertical | `VStack(spacing:)` |
| Item spacing: N | `spacing: .dsSpacingN` |
| Padding: top/bottom | `.padding(.vertical, .dsSpacingN)` |
| Padding: left/right | `.padding(.horizontal, .dsSpacingN)` |
| Padding: all equal | `.padding(.dsSpacingN)` |
| Fill container (horizontal) | `.frame(maxWidth: .infinity)` |
| Fill container (vertical) | `.frame(maxHeight: .infinity)` |
| Hug contents | No frame constraint (natural sizing) |
| Fixed width | `.frame(width: N)` |
| Fixed height | `.frame(height: N)` |
| Align items: center | `alignment: .center` |
| Align items: leading | `alignment: .leading` |
| Space between | `Spacer()` between items |
| Clip contents | `.clipped()` |
| Corner radius: 4/8/12/16 | `.cornerRadius(.small/.regular/.medium/.large)` |
| Corner radius: height/2 | `.cornerRadius(.full)` |

## Figma Fill-to-DSColor Matching

When you encounter a fill color in Figma:

1. **Check if hex matches an existing DSColor token** by searching `DSColor+Semantic.swift` and asset catalog
2. **If it matches a primitive** in `DSColor+Core.swift`, find the semantic alias
3. **If no semantic token exists**, create one following the naming convention:
   ```
   bg<Context><State>       (backgrounds)
   text<Context><State>     (text colors)
   icon<Context><State>     (icon/image tints)
   border<Context><State>   (borders)
   ```
4. **Add the color asset** to `DesignSystem/UIFoundation/Resources/Assets/` with light + dark variants
5. **Add the Swift property** to the appropriate `DSColor+*.swift` extension file

## Figma Typography-to-DSFont Matching

| Figma Style Name Pattern | Swift Font Token |
|---|---|
| `Display / Numbers / Large` | `Font.dsDisplayLarge` (40pt) |
| `Display / Numbers / Regular` | `Font.dsDisplayRegular` (32pt) |
| `Heading / H1` | `Font.dsHeading1` (36pt, 32pt RTL) |
| `Heading / H2` | `Font.dsHeading2` (24pt) |
| `Heading / H3` | `Font.dsHeading3` (24pt, 20pt RTL) |
| `Heading / H4` | `Font.dsHeading4` (20pt, 18pt RTL) |
| `Heading / H5` | `Font.dsHeading5` (16pt) |
| `Body / Base` | `Font.dsBodyBase` (14pt) |
| `Body / Small` | `Font.dsBodySmall` (12pt) |
| `Body / Micro` | `Font.dsBodyMicro` (8pt) |
| `Action / Button (CTA)` | `Font.dsCta` (14pt) |
| `Action / Hyperlink / Base` | `Font.dsHyperlinkBase` (14pt) |
| `Action / Hyperlink / Small` | `Font.dsHyperlinkSmall` (12pt) |
| `Caption-Overline / Caption` | `Font.dsCaption` (12pt) |
| `Caption-Overline / Overline` | `Font.dsOverline` (12pt) |

For weight modifiers:
| Figma Weight | Swift |
|---|---|
| Light / 300 | `.weight(.light)` |
| Regular / 400 | (default, no modifier) |
| Medium / 500 | `.weight(.medium)` |
| Bold / 700 | `.weight(.bold)` |
