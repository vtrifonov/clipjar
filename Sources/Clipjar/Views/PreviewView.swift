import AppKit
import ClipjarCore
import SwiftUI

/// The selected clip in full on the right of the panel.
struct PreviewView: View {
    let model: HistoryViewModel

    var body: some View {
        if let clip = model.selectedClip, let id = clip.id {
            VStack(alignment: .leading, spacing: 12) {
                PreviewHeader(clip: clip)
                content(clip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(id)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func content(_ clip: Clip) -> some View {
        switch clip.kind {
        case .text, .link: TextPreview(text: clip.plainText, terms: model.highlightTerms)
        case .image: ImagePreview(clip: clip, blobsDirectory: model.store.blobsDirectory)
        case .file: FilesPreview(urls: clip.fileURLs.compactMap(URL.init(string:)))
        }
    }
}

private struct PreviewHeader: View {
    let clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label(DisplayFormat.previewSummary(clip), systemImage: Self.icon(clip.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if clip.isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
            }
            Text(origin)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var origin: String {
        let date = clip.lastCopiedAt.formatted(date: .abbreviated, time: .shortened)
        guard let app = clip.sourceAppName else { return "Copied · \(date)" }
        return "Copied from \(app) · \(date)"
    }

    static func icon(_ kind: ClipKind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

// MARK: Text

private struct TextPreview: View {
    static let limit = 20_000

    let text: String
    let terms: [String]

    var body: some View {
        let shown = String(text.prefix(Self.limit))
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(highlighted(shown))
                    .font(.body.monospaced())
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if shown.count < text.count {
                    Text("Showing first \(Self.limit.formatted()) of \(text.count.formatted()) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    private func highlighted(_ s: String) -> AttributedString {
        var attributed = AttributedString(s)
        for match in Highlighter.ranges(of: terms, in: s) {
            guard let range = Range(match, in: attributed) else { continue }
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
            attributed[range].foregroundColor = .accentColor
        }
        return attributed
    }
}

// MARK: Image

private struct ImagePreview: View {
    let clip: Clip
    let blobsDirectory: URL

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?
    @State private var unavailable = false

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let shown = image ?? thumbnail {
                    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                    Image(nsImage: shown)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .frame(maxWidth: maxPointSize.width, maxHeight: maxPointSize.height)
                        .accessibilityLabel(accessibilityLabel)
                } else if unavailable {
                    Label("Image unavailable", systemImage: "photo")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .task(id: clip.id) {
                await load(paneSize: geometry.size)
            }
        }
    }

    private func load(paneSize: CGSize) async {
        image = nil
        unavailable = false
        guard let path = clip.imagePath else {
            unavailable = true
            return
        }
        let pixels = Int((max(paneSize.width, paneSize.height) * displayScale).rounded(.up))
        let loaded = await ImageCache.shared.image(at: blobsDirectory.appendingPathComponent(path), maxPixelSize: max(pixels, 1))
        guard !Task.isCancelled else { return }
        image = loaded
        unavailable = loaded == nil
    }

    private var thumbnail: NSImage? {
        guard !unavailable, let path = clip.thumbnailPath else { return nil }
        let url = blobsDirectory.appendingPathComponent(path)
        return ImageCache.shared.cachedImage(ImageCache.key(url, maxPixelSize: 56))
    }

    /// Never larger than the image's own pixels.
    private var maxPointSize: CGSize {
        guard let w = clip.imageWidth, let h = clip.imageHeight else { return CGSize(width: CGFloat.infinity, height: .infinity) }
        return CGSize(width: CGFloat(w) / displayScale, height: CGFloat(h) / displayScale)
    }

    private var accessibilityLabel: String {
        guard let w = clip.imageWidth, let h = clip.imageHeight else { return "Image" }
        return "Image, \(w) by \(h) pixels"
    }
}

// MARK: Files

private struct FileInfo: Sendable {
    var exists: Bool
    var isDirectory: Bool
    var size: Int?
}

private struct FilesPreview: View {
    static let limit = 20

    let urls: [URL]
    @State private var info: [URL: FileInfo] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(urls.prefix(Self.limit), id: \.self) { url in
                    FileRow(url: url, info: info[url])
                }
                if urls.count > Self.limit {
                    Text("+\((urls.count - Self.limit).formatted()) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 42)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: urls) {
            let shown = Array(urls.prefix(Self.limit))
            info = await Task.detached(priority: .userInitiated) { Self.stat(shown) }.value
        }
    }

    nonisolated private static func stat(_ urls: [URL]) -> [URL: FileInfo] {
        var result: [URL: FileInfo] = [:]
        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let size = exists && !isDirectory.boolValue ? (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize : nil
            result[url] = FileInfo(exists: exists, isDirectory: isDirectory.boolValue, size: size)
        }
        return result
    }
}

private struct FileRow: View {
    let url: URL
    let info: FileInfo?

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                detail
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        if info?.exists == false {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
        }
    }

    @ViewBuilder private var detail: some View {
        if let info {
            Group {
                if !info.exists {
                    Text("No longer exists")
                } else if info.isDirectory {
                    Text("Folder")
                } else if let size = info.size {
                    Text(DisplayFormat.bytes(size))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
