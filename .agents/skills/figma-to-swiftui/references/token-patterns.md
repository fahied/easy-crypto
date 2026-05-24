# Token Patterns

Exact patterns for declaring and using design tokens in the Emirates DesignSystem.

## Color Tokens

### DSColor struct (wraps SwiftUI Color)

```swift
public struct DSColor: Sendable {
    public let color: Color

    internal init(_ color: Color)
    internal init(asset: String, bundle: Bundle)
    internal init(asset: String) // uses .module bundle

    public static func dynamicColor(light: DSColor, dark: DSColor) -> DSColor
    public func opacity(_ fraction: Double) -> DSColor
    public static let clear = DSColor(Color.clear)
}
```

### Conformances

```swift
extension DSColor: ShapeStyle {
    public func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        return self.color
    }
}

extension DSColor: View {}
```

### Hierarchical color organization (Brand/Global primitives)

```swift
public extension DSColor {
    enum Brand {
        public enum Primary {
            /// token: colour.brand.primary.ek-red
            public static let ekRed = DSColor(asset: "ekRed")
            public static let ekWhite = DSColor(asset: "ekWhite")
            public static let ekBlack = DSColor(asset: "ekBlack")
        }

        public enum Neutral {
            /// token: colour.brand.neutral.grey-800
            public static let grey800 = DSColor(asset: "grey800")
            public static let grey700 = DSColor(asset: "grey700")
            // ... grey600 through grey100, white
        }
    }

    enum Global {
        public enum Skywards { /* blue, silver, gold, platinum, io + gradients */ }
        public enum Functional { /* information, neutral, negative + medium/light */ }
    }
}
```

### Semantic color tokens (component-specific)

```swift
public extension DSColor {
    // Background tokens
    /// token: colour/background/action/primary/enabled
    static let bgActionPrimaryEnabled = DSColor(asset: "bgActionPrimaryEnabled")
    static let bgActionPrimaryTapped = DSColor(asset: "bgActionPrimaryTapped")
    static let bgActionPrimaryDisabled = DSColor(asset: "bgActionPrimaryDisabled")
    static let bgActionPrimaryPending = DSColor(asset: "bgActionPrimaryPending")

    // Text tokens
    static let textActionPrimaryEnabled = DSColor(asset: "textActionPrimaryEnabled")
    static let textGeneralCopy = DSColor(asset: "textGeneralCopy")

    // Icon tokens
    static let iconGeneralEnabled = DSColor(asset: "iconGeneralEnabled")
    static let iconActionPrimaryEnabled = DSColor(asset: "iconActionPrimaryEnabled")

    // Badge tokens
    static let bgBadgeNeutral = DSColor(asset: "bgBadgeNeutral")
    static let textBadgeNeutral = DSColor(asset: "textBadgeNeutral")

    // Container tokens
    static let bgContainerSurfaceBright = DSColor(asset: "bgContainerSurfaceBright")
    static let bgContainerSurfaceLower = DSColor(asset: "bgContainerSurfaceLower")

    // Skeleton
    static let bgSkeleton = DSColor(asset: "bgSkeleton")
}
```

### Naming convention

Figma token path → Swift property name:
```
colour/background/action/primary/enabled  →  bgActionPrimaryEnabled
colour/text/badge/neutral                 →  textBadgeNeutral
colour/icon/general/enabled               →  iconGeneralEnabled
colour/background/container/surface/bright → bgContainerSurfaceBright
```

**Pattern**: Strip `colour/`, then camelCase segments. Abbreviate `background` → `bg`, `text` stays `text`, `icon` stays `icon`.

### Usage in views

```swift
.foregroundStyle(DSColor.textGeneralCopy)     // as ShapeStyle
.background(DSColor.bgContainerSurfaceBright)  // as View
.foregroundStyle(variant.textColor)             // from enum computed property
```

## Spacing Tokens

### CGFloat extension pattern

```swift
extension CGFloat {
    /// Design System - spacing.app.2px
    public static let dsSpacing2: CGFloat = 2
    public static let dsSpacing4: CGFloat = 4
    public static let dsSpacing6: CGFloat = 6
    public static let dsSpacing8: CGFloat = 8
    public static let dsSpacing12: CGFloat = 12
    public static let dsSpacing16: CGFloat = 16
    public static let dsSpacing24: CGFloat = 24
    public static let dsSpacing32: CGFloat = 32
    public static let dsSpacing40: CGFloat = 40
    public static let dsSpacing48: CGFloat = 48
    public static let dsSpacing56: CGFloat = 56
    public static let dsSpacing64: CGFloat = 64
    public static let dsSpacing72: CGFloat = 72
    public static let dsSpacing80: CGFloat = 80
    public static let dsSpacing96: CGFloat = 96
}
```

### Usage

```swift
.padding(.vertical, .dsSpacing12)
.padding(.horizontal, .dsSpacing8)
VStack(spacing: .dsSpacing16) { ... }
HStack(spacing: .dsSpacing4) { ... }
```

## Rounding Tokens

### DSRounding enum

```swift
public enum DSRounding: Sendable {
    case small    // 4px
    case regular  // 8px
    case medium   // 12px
    case large    // 16px
    case full     // .infinity

    public var radius: CGFloat {
        switch self {
        case .small: return 4
        case .regular: return 8
        case .medium: return 12
        case .large: return 16
        case .full: return .infinity
        }
    }
}
```

### Usage

```swift
.cornerRadius(.regular)        // View+DSRounding extension
.cornerRadius(variant.rounding) // from enum computed property
```

## Shadow Tokens

### DSShadow enum

```swift
public enum DSShadow {
    case raisedSmall    // shadow.app.raised.small
    case raisedMedium   // shadow.app.raised.medium
    case raisedLarge    // shadow.app.raised.large
    case overlay        // shadow.app.overlay

    var color: Color { /* dynamic light/dark */ }
    public var radius: CGFloat { /* 8, 12, 12, 37.5 */ }
    public var x: CGFloat { /* 2, 2, 0, 0 */ }
    public var y: CGFloat { /* 4, 8, -12, 55 */ }
}
```

### Usage (via View extension)

```swift
.dsShadow(.raisedSmall)
.dsShadow(.raisedMedium)
```

## Typography Tokens

### Font extension pattern

```swift
extension Font {
    /// token: type.app.display.numbers.large
    public static let dsDisplayLarge: Font = .custom(DSFont.defaultAppleFamily, size: 40)

    /// token: type.app.heading.1
    public static let dsHeading1: Font = .custom(DSFont.emirates, size: DSFont.isRTL ? 32 : 36)

    /// token: type.app.body.base
    public static let dsBodyBase: Font = .custom(DSFont.defaultAppleFamily, size: 14)
    public static let dsBodySmall: Font = .custom(DSFont.defaultAppleFamily, size: 12)

    /// token: type.app.action.button
    public static let dsCta: Font = .custom(DSFont.defaultAppleFamily, size: 14)

    /// token: type.app.caption-overline.caption
    public static let dsCaption: Font = .custom(DSFont.defaultAppleFamily, size: 12)
    public static let dsOverline: Font = .custom(DSFont.defaultAppleFamily, size: 12)
}
```

### Usage

```swift
.font(.dsBodyBase)
.font(.dsCaption.weight(.light))
.font(.dsCta)
.font(.dsHeading1)
```

### DSFont struct for advanced usage

```swift
// Via View modifier
.dsFont(DSFont.Heading.h3)

// Direct font access
token.font  // SwiftUI Font
token.size  // CGFloat
```

## Gradient Pattern

```swift
LinearGradient(dsColors: [.color1, .color2], startPoint: .leading, endPoint: .trailing)
LinearGradient.horizontal(.color1, .color2)
LinearGradient.vertical(.color1, .color2)
LinearGradient.diagonal(.color1, .color2)
```

## Icon Token Pattern

```swift
// DSIcon provides static string constants for icon asset names
Image(DSIcon.placeholder)
Image(DSIcon.chevronRight)
Image(DSIcon.chevronLeft)
Image(DSIcon.chevronDown)
Image(DSIcon.car)

// Icon styling
Image(DSIcon.chevronRight)
    .renderingMode(.template)
    .resizable()
    .foregroundStyle(DSColor.iconGeneralEnabled)
    .frame(width: 16, height: 16)
```

## Animation Token Pattern

```swift
// DS motion tokens
.animation(.dsExpressive2, value: someValue)
withAnimation(.dsExpressive2) { ... }
```

## Aspect Ratio Pattern

```swift
// AspectRatio enum
AspectRatio.threeToOne.ratio  // CGFloat
AspectRatio.twoToOne.ratio    // CGFloat
```
