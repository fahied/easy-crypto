# Completion Checklist

Verify every item before marking a component as done.

## Naming & Structure
- [ ] Component struct named `DS<ComponentName>` with `public` modifier
- [ ] File placed in `DesignSystem/CoreComponents/<ComponentName>/`
- [ ] Enums for variants/types/states declared with descriptive names
- [ ] `CaseIterable` on enums that need ForEach iteration
- [ ] `Sendable` added where appropriate (simple value types, config structs)
- [ ] Separate file per struct/enum when complex (styles, models, sub-views)
- [ ] Figma link in file header comment

## API Design
- [ ] All public properties declared as `public let` (or `@Binding` for parent-controlled state)
- [ ] `public init(...)` with sensible default values
- [ ] No redundant types — use native Swift/SwiftUI types when they suffice
- [ ] Optional closures typed as `(() -> Void)?` (or `@Sendable` variant)
- [ ] Config structs for complex grouped parameters

## Tokens
- [ ] ALL colors use `DSColor` semantic tokens (no hardcoded hex/Color.red)
- [ ] ALL spacing uses `.dsSpacingN` constants (no hardcoded CGFloat values)
- [ ] ALL corner radii use `DSRounding` enum (`.cornerRadius(.medium)`)
- [ ] ALL typography uses `Font` DS extensions (`.font(.dsBodyBase)`)
- [ ] ALL shadows use `.dsShadow()` modifier
- [ ] ALL icons use `DSIcon` string constants

## Layout & Styling
- [ ] Uses `foregroundStyle()` (NOT deprecated `foregroundColor()`)
- [ ] Correct spacing hierarchy (VStack/HStack spacing from tokens)
- [ ] Proper padding from tokens
- [ ] Frame constraints match Figma specifications
- [ ] Background colors applied from DS tokens

## States & Interactivity
- [ ] All Figma states implemented (enabled, disabled, pressed, pending, skeleton)
- [ ] `ButtonStyle` with `configuration.isPressed` for press feedback
- [ ] `.disabled()` modifier applied when status != .enabled
- [ ] Loading/spinner state handled (DSLoader)
- [ ] Animation on state transitions (`.animation(.easeInOut(duration: 0.2))`)

## Accessibility
- [ ] VoiceOver labels on interactive elements
- [ ] `.accessibilityElement(children:)` for grouped content
- [ ] `.accessibilityValue` for dynamic content (carousels, sliders)
- [ ] `.accessibilityAdjustableAction` for carousel/paginated content
- [ ] `.accessibilityHidden(true)` for decorative elements

## Dark Mode & RTL
- [ ] Colors support light/dark via asset catalog or `dynamicColor(light:dark:)`
- [ ] RTL-aware font sizes where applicable (`DSFont.isRTL` ternary)
- [ ] Layout supports both LTR and RTL reading directions

## Previews
- [ ] `#Preview` blocks present for all major variant combinations
- [ ] `traits: .modifier(PreviewFontRegistration())` included for custom fonts
- [ ] Realistic sample data (not placeholder text)
- [ ] No `@State` in preview body (wrap in `PreviewState` struct if `@Binding` needed)
- [ ] Descriptive preview names
- [ ] ScrollView wrapper for long content

## Companion Demo (if applicable)
- [ ] Demo view in `Companion/Companion/Components/<Category>/Components/`
- [ ] Interactive `@State` controls for all configurable properties
- [ ] `ControlsCard` wrapper for controls section
- [ ] `.withToolbar(name:)` modifier
- [ ] Simple `#Preview` block

## Build
- [ ] Compiles with: `xcodebuild -scheme DesignSystem clean build test -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'`
- [ ] No warnings introduced
- [ ] No TODO comments left in code
