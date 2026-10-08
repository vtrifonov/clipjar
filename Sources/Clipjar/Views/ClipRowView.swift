import AppKit
import ClipjarCore
import SwiftUI

/// The scrolling clip list on the left of the panel.
struct ClipListView: View {
    let model: HistoryViewModel
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                            rowView(row, index: index, now: timeline.date)
                        }
                    }
                    .padding(6)
                    .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.9), value: model.selectedID)
                }
                .onChange(of: model.scrollTarget) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: nil)
                }
            }
        }
        .frame(width: 300)
    }

    private func rowView(_ row: ClipRow, index: Int, now: Date) -> some View {
        ClipRowView(
            row: row,
            index: index,
            isSelected: row.id == model.selectedID,
            terms: model.highlightTerms,
            blobsDirectory: model.store.blobsDirectory,
            now: now,
            selectionNamespace: selection
        )
        .id(row.id)
        .contentShape(Rectangle())
        .onAppear { model.rowAppeared(index: index) }
        .onContinuousHover { phase in
            if case .active = phase { model.hover(id: row.id, mouseLocation: NSEvent.mouseLocation) }
        }
        .onTapGesture { model.activate(id: row.id, copyOnly: NSEvent.modifierFlags.contains(.option)) }
        .contextMenu {
            Button("Paste") { perform(.activate(copyOnly: false), on: row) }
                .keyboardShortcut(.return, modifiers: [])
            Button("Copy") { perform(.activate(copyOnly: true), on: row) }
                .keyboardShortcut(.return, modifiers: .option)
            Button(row.isPinned ? "Unpin" : "Pin") { perform(.togglePin, on: row) }
                .keyboardShortcut("p", modifiers: .command)
            Divider()
            Button("Delete") { perform(.delete, on: row) }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .accessibilityAction(named: row.isPinned ? "Unpin" : "Pin") { perform(.togglePin, on: row) }
        .accessibilityAction(named: "Delete") { perform(.delete, on: row) }
        .accessibilityAction(named: "Copy") { perform(.activate(copyOnly: true), on: row) }
    }

    private func perform(_ cmd: PanelCommand, on row: ClipRow) {
        model.select(id: row.id)
        model.handle(cmd)
    }
}

struct ClipRowView: View {
    let row: ClipRow
    let index: Int
    let isSelected: Bool
    let terms: [String]
    let blobsDirectory: URL
    let now: Date
    let selectionNamespace: Namespace.ID

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var thumbnail: NSImage?

    private static let thumbnailPixels = 56

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let swatch { swatchView(swatch) }
                    Text(title)
                        .font(isCode ? .body.monospaced() : .body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 4) {
                    if row.kind == .image { appIcon(size: 12) }
                    Text(DisplayFormat.secondaryLine(row, now: now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background { if isSelected { pill } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DisplayFormat.rowAccessibilityLabel(row, now: now))
        .accessibilityHint("Press Return to paste")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Parts

    @ViewBuilder private var leading: some View {
        if row.kind == .image {
            thumbnailView
        } else {
            appIcon(size: 20)
        }
    }

    private var thumbnailView: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return ZStack {
            if let image = thumbnail ?? cachedThumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 28, height: 28)
        .background(.quaternary.opacity(0.5))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
        .task(id: row.thumbnailPath) {
            guard let url = thumbnailURL else { return }
            thumbnail = await ImageCache.shared.image(at: url, maxPixelSize: Self.thumbnailPixels)
        }
    }

    @ViewBuilder private func appIcon(size: CGFloat) -> some View {
        if let icon = ImageCache.shared.appIcon(bundleID: row.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.tertiary)
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 6) {
            if row.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func swatchView(_ color: TextHeuristics.RGBA) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(.sRGB, red: color.r, green: color.g, blue: color.b, opacity: color.a))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
            )
            .frame(width: 12, height: 12)
            .accessibilityLabel("Colour \(Self.hex(color))")
    }

    private var pill: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let increased = contrast == .increased
        return shape
            .fill(Color.accentColor.opacity(increased ? 0.35 : 0.22))
            .overlay { if increased { shape.strokeBorder(Color.accentColor, lineWidth: 1) } }
            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
    }

    // MARK: Content

    private var isCode: Bool {
        row.kind == .text && TextHeuristics.isCodeLike(row.previewText)
    }

    private var swatch: TextHeuristics.RGBA? {
        row.kind == .text ? TextHeuristics.hexColor(row.previewText) : nil
    }

    private var thumbnailURL: URL? {
        row.thumbnailPath.map { blobsDirectory.appendingPathComponent($0) }
    }

    private var cachedThumbnail: NSImage? {
        thumbnailURL.flatMap { ImageCache.shared.cachedImage(ImageCache.key($0, maxPixelSize: Self.thumbnailPixels)) }
    }

    /// Links show their domain in the primary colour and the rest dimmed; search matches are bold and accented.
    private var title: AttributedString {
        let text = row.previewText
        var attributed = AttributedString(text)
        if row.kind == .link {
            attributed.foregroundColor = .secondary
            if let domain = TextHeuristics.linkDomain(text),
               let found = text.range(of: domain, options: .caseInsensitive),
               let range = Range(found, in: attributed) {
                attributed[range].foregroundColor = .primary
            }
        }
        for match in Highlighter.ranges(of: terms, in: text) {
            guard let range = Range(match, in: attributed) else { continue }
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
            attributed[range].foregroundColor = .accentColor
        }
        return attributed
    }

    static func hex(_ c: TextHeuristics.RGBA) -> String {
        String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }
}
