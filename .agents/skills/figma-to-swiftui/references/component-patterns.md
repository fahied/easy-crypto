# Component Patterns

Exact code patterns extracted from the Emirates DesignSystem repository. Follow these precisely for deterministic output.

## File Header

```swift
//
//  DS<ComponentName>.swift
//  DesignSystem
//
//  Created by <Author> on <Date>.
//
//  Figma: <figma_url>
//

import SwiftUI
import UIFoundation
```

## Enum Patterns

### Top-level enums (for cross-component reuse)

```swift
public enum DS<Component>Status: Hashable, CaseIterable {
    case enabled
    case disabled
    case pending
    case skeleton
}

public enum DS<Component>Types: CaseIterable {
    case primary
    case secondary
    // ...
}

public enum DS<Component>Variants {
    case regular
    case small

    var verticalPadding: CGFloat {
        switch self {
        case .regular: .dsSpacing12
        case .small: .dsSpacing8
        }
    }
}
```

### Nested enums (for component-scoped variants)

```swift
public struct DSBadge: View, Sendable {
    public enum Variant: String, Sendable {
        case alert
        case warning
        case positive
        // ...

        var backgroundColor: DSColor {
            switch self {
            case .alert: return .bgBadgeWarningPending
            case .warning: return .bgBadgeNegative
            case .positive: return .bgBadgePositive
            }
        }

        var textColor: DSColor {
            switch self {
            case .alert: return .textBadgeWarningPending
            // ...
            }
        }
    }
}

extension DSBadge.Variant: CaseIterable {}
```

**Decision**: Use nested enum when variants are only meaningful within the component. Use top-level enum when shared across components or the enum has many computed properties that would bloat the struct.

## Struct Declaration

### Simple component (no generic content)

```swift
public struct DS<Name>: View, Sendable {
    public let text: String
    public let variant: Variant

    public init(text: String, variant: Variant = .neutral) {
        self.text = text
        self.variant = variant
    }

    public var body: some View {
        Text(text)
            .font(.dsCaption.weight(.light))
            .foregroundStyle(variant.textColor)
            .padding(.vertical, .dsSpacing4)
            .padding(.horizontal, .dsSpacing8)
            .background(variant.backgroundColor)
            .cornerRadius(.regular)
    }
}
```

### Component with actions and icons

```swift
public struct DS<Name>: View {
    public let title: String
    public let type: DS<Name>Types
    public let variant: DS<Name>Variants
    public let status: DS<Name>Status
    public let leadingIcon: Image?
    public let trailingIcon: Image?
    public let action: () -> Void

    private var style: AnyButtonStyle {
        switch type {
        case .primary: AnyButtonStyle(DS<Name>PrimaryStyle(status: status))
        case .secondary: AnyButtonStyle(DS<Name>SecondaryStyle(status: status))
        }
    }

    public init(
        _ title: String,
        type: DS<Name>Types = .primary,
        variant: DS<Name>Variants = .regular,
        status: DS<Name>Status = .enabled,
        leadingIcon: Image? = nil,
        trailingIcon: Image? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.type = type
        self.variant = variant
        self.status = status
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: .dsSpacing4) {
                icon(leadingIcon)
                Text(title)
                    .font(.dsCta)
                    .multilineTextAlignment(.center)
                icon(trailingIcon)
            }
            .padding(.vertical, variant.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(style)
        .disabled(status != .enabled)
    }

    @ViewBuilder
    private func icon(_ icon: Image?) -> some View {
        if let icon {
            icon
                .resizable()
                .renderingMode(.template)
                .frame(.square(16))
        } else {
            EmptyView()
        }
    }
}
```

### Component with @Binding

```swift
public struct DS<Name>: View {
    @Binding private var selectedTabId: String
    private let tabs: [DS<Name>Tab]

    public init(
        tabs: [DS<Name>Tab],
        selectedTabId: Binding<String>
    ) {
        self.tabs = tabs
        self._selectedTabId = selectedTabId
    }
}
```

### Component with generic content

```swift
public struct DS<Name><Content: View>: View {
    let content: AnyView

    public init(
        title: String,
        content: some View = Group { }
    ) {
        self.title = title
        self.content = AnyView(content)
    }
}
```

### Config structs for complex parameters

```swift
public struct DS<Name>Config: Sendable {
    let title: String
    let icon: Image?
    let action: @Sendable () -> Void

    public init(title: String, icon: Image?, action: @Sendable @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
}
```

## ButtonStyle Pattern

```swift
struct DS<Name><Variant>Style: ButtonStyle {
    let status: DS<Name>Status

    init(status: DS<Name>Status = .enabled) {
        self.status = status
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(textColor(for: configuration.isPressed))
            .background(backgroundColor(for: configuration.isPressed))
            .cornerRadius(.medium)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }

    private func backgroundColor(for isPressed: Bool) -> DSColor {
        switch status {
        case .enabled:
            return isPressed ? .bgActionPrimaryTapped : .bgActionPrimaryEnabled
        case .disabled:
            return .bgActionPrimaryDisabled
        case .pending:
            return .bgActionPrimaryPending
        case .skeleton:
            return .bgSkeleton
        }
    }

    private func textColor(for isPressed: Bool) -> DSColor {
        switch status {
        case .enabled:
            return isPressed ? .textActionPrimaryPressed : .textActionPrimaryEnabled
        case .disabled:
            return .textActionPrimaryDisabled
        case .pending, .skeleton:
            return .textActionPrimaryDisabled
        }
    }
}
```

## Preview Patterns

### Simple component — all variants via ForEach

```swift
#Preview("DS<Name>", traits: .modifier(PreviewFontRegistration())) {
    VStack(spacing: .dsSpacing12) {
        ForEach(DS<Name>.Variant.allCases, id: \.self) { variant in
            DS<Name>(text: variant.rawValue, variant: variant)
        }
    }
}
```

### Complex component — nested loops for type × status × variant

```swift
#Preview("DS<Name> - Regular") {
    ScrollView {
        VStack(spacing: .dsSpacing32) {
            ForEach(DS<Name>Types.allCases, id: \.self) { type in
                VStack(spacing: .dsSpacing24) {
                    Text(verbatim: "\(type)")
                    ForEach(DS<Name>Status.allCases, id: \.self) { status in
                        VStack(spacing: .dsSpacing12) {
                            DS<Name>(
                                "\(status)",
                                type: type,
                                variant: .regular,
                                status: status
                            ) { }
                        }
                    }
                }
            }
            .padding()
        }
    }
}
```

### Preview requiring @Binding — wrap in PreviewState struct

```swift
#Preview("DSNotificationMenu • Tabs only", traits: .modifier(PreviewFontRegistration())) {
    struct PreviewState: View {
        @State private var selectedId = "trips"
        var body: some View {
            DSNotificationMenu(
                tabs: [
                    DSNotificationMenuTab(id: "trips", title: "Trips"),
                    DSNotificationMenuTab(id: "offers", title: "News & Offers")
                ],
                selectedTabId: $selectedId
            )
            .padding()
        }
    }
    return PreviewState()
}
```

### Multiple preview blocks for different configurations

```swift
#Preview("DS<Name> — Carousel", traits: .modifier(PreviewFontRegistration())) {
    // carousel configuration...
}

#Preview("DS<Name> — Single", traits: .modifier(PreviewFontRegistration())) {
    // single configuration...
}
```

## Companion Demo View Pattern

```swift
import SwiftUI
import DesignSystem

struct <Name>View: View {
    @State private var selectedType: DS<Name>Types = .primary
    @State private var selectedStatus: DS<Name>Status = .enabled
    @State private var showLeadingIcon = false

    var body: some View {
        VStack(spacing: .dsSpacing40) {
            /// Controls
            ControlsCard {
                HStack {
                    Text("Type")
                        .font(.dsBodyBase)
                        .foregroundStyle(.textGeneralCopy)
                    Spacer()
                    Picker("Type", selection: $selectedType) {
                        ForEach(DS<Name>Types.allCases, id: \.self) { type in
                            Text(String(describing: type).capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToggleControl(title: "Leading Icon", isOn: $showLeadingIcon)
            }

            /// Demo
            DS<Name>(
                "Sample",
                type: selectedType,
                status: selectedStatus,
                leadingIcon: showLeadingIcon ? Image(DSIcon.placeholder) : nil
            ) { }
            .padding()

            Spacer()
        }
        .background(.bgContainerSurfaceBright)
        .withToolbar(name: "<Component Name>")
    }
}

#Preview {
    <Name>View()
}
```

## Folder Structure

```
DesignSystem/CoreComponents/<ComponentName>/
├── DS<ComponentName>.swift           # Main component + enums + previews
├── DS<ComponentName>PrimaryStyle.swift   # ButtonStyle (if needed)
├── DS<ComponentName>SecondaryStyle.swift  # Additional styles
├── <SubComponent>.swift              # Sub-views (if complex)
└── <ComponentName>Model.swift        # Data model (if needed)

Companion/Companion/Components/<Category>/Components/
└── <ComponentName>View.swift         # Interactive demo view
```
