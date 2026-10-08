import Foundation

public enum ClipBuilder {
    /// Pure. Blob paths left nil (the store fills them for images).
    public static func makeClip(from c: CapturedContent, hash: String, source: SourceApp?, now: Date) -> Clip {
        var clip = Clip(
            kind: c.kind,
            plainText: "",
            previewText: "",
            searchText: "",
            contentHash: hash,
            sourceBundleID: source?.bundleID,
            sourceAppName: source?.name,
            createdAt: now,
            lastCopiedAt: now,
            isPinned: false,
            byteSize: 0
        )
        switch c.kind {
        case .text, .link:
            clip.plainText = c.plainText
            clip.previewText = TextHeuristics.previewText(c.plainText)
            clip.searchText = SearchFolding.fold(c.plainText)
            clip.rtfData = c.rtf
            clip.htmlData = c.html
            clip.byteSize = c.plainText.utf8.count
        case .file:
            clip.plainText = c.fileURLs.map(\.path).joined(separator: "\n")
            clip.fileURLs = c.fileURLs.map(\.absoluteString)
            clip.previewText = TextHeuristics.previewText(c.fileURLs.map(\.lastPathComponent).joined(separator: ", "))
            clip.searchText = SearchFolding.fold(clip.plainText)
        case .image:
            let w = c.width ?? 0
            let h = c.height ?? 0
            clip.previewText = "Image \(w)\u{00D7}\(h)"
            clip.imageType = c.image?.uti
            clip.byteSize = c.image?.data.count ?? 0
            clip.imageWidth = c.width
            clip.imageHeight = c.height
        }
        return clip
    }
}
