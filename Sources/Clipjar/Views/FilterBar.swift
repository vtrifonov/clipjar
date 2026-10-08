import ClipjarCore
import SwiftUI

/// Kind chips under the header; ⇥ / ⇧⇥ cycle through them.
struct FilterBar: View {
    @Bindable var model: HistoryViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach([FilterChip.all, .text, .links, .images, .files], id: \.self) { chip($0) }
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 14)
                .accessibilityHidden(true)
            chip(.pinned)
            Spacer(minLength: 8)
            if !model.isMatchCountPending {
                Text(DisplayFormat.countLabel(model.matchCount))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private func chip(_ chip: FilterChip) -> some View {
        FilterChipButton(title: Self.title(chip), icon: Self.icon(chip), isSelected: model.filter == chip) {
            model.filter = chip
        }
    }

    static func title(_ chip: FilterChip) -> String {
        switch chip {
        case .all: "All"
        case .text: "Text"
        case .links: "Links"
        case .images: "Images"
        case .files: "Files"
        case .pinned: "Pinned"
        }
    }

    static func icon(_ chip: FilterChip) -> String {
        switch chip {
        case .all: "tray.full"
        case .text: "text.alignleft"
        case .links: "link"
        case .images: "photo"
        case .files: "doc"
        case .pinned: "pin"
        }
    }
}

private struct FilterChipButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.callout.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Filter: \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(0.18)) }
        return isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear)
    }
}
