import Foundation

/// User-facing strings for the panel.
public enum DisplayFormat {
    private static let separator = " · "
    private static let accessibilityPreviewLimit = 100

    /// "1 clip", "1,204 clips".
    public static func countLabel(_ n: Int, locale: Locale = .current) -> String {
        "\(number(n, locale: locale)) \(n == 1 ? "clip" : "clips")"
    }

    /// "now" under a minute, else a short relative time such as "2 min. ago". (`.short`, not
    /// `.abbreviated`: on macOS 26 the latter renders as "2m ago".)
    public static func relativeTime(_ d: Date, now: Date, locale: Locale = .current) -> String {
        if now.timeIntervalSince(d) < 60 { return "now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: d, relativeTo: now)
    }

    /// "[domain · ]App · time"; files: "3 files · App · time"; a missing app name is omitted.
    public static func secondaryLine(_ row: ClipRow, now: Date, locale: Locale = .current) -> String {
        var parts: [String] = []
        switch row.kind {
        case .link:
            if let domain = TextHeuristics.linkDomain(row.previewText) { parts.append(domain) }
        case .file:
            parts.append(fileCount(row.fileCount, locale: locale))
        case .text, .image:
            break
        }
        if let app = row.sourceAppName { parts.append(app) }
        parts.append(relativeTime(row.lastCopiedAt, now: now, locale: locale))
        return parts.joined(separator: separator)
    }

    /// "Text · 1,204 characters · 37 lines" | "Link · example.com" | "Image · 1200 × 800 px · 245 KB" | "3 files".
    public static func previewSummary(_ clip: Clip, locale: Locale = .current) -> String {
        switch clip.kind {
        case .text:
            let characters = clip.plainText.count
            let lines = clip.plainText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
            return [
                "Text",
                "\(number(characters, locale: locale)) \(characters == 1 ? "character" : "characters")",
                "\(number(lines, locale: locale)) \(lines == 1 ? "line" : "lines")",
            ].joined(separator: separator)
        case .link:
            guard let domain = TextHeuristics.linkDomain(clip.plainText) else { return "Link" }
            return "Link" + separator + domain
        case .image:
            var parts = ["Image"]
            if let w = clip.imageWidth, let h = clip.imageHeight { parts.append("\(w) × \(h) px") }
            parts.append(bytes(clip.byteSize))
            return parts.joined(separator: separator)
        case .file:
            return fileCount(clip.fileURLs.count, locale: locale)
        }
    }

    /// Copy-only wording when pasting is off or Accessibility is not granted.
    public static func footerHints(pasteOnSelect: Bool, trusted: Bool, selectedPinned: Bool) -> String {
        let activate = pasteOnSelect && trusted ? ["⏎ Paste", "⌥⏎ Copy"] : ["⏎ Copy"]
        let pin = selectedPinned ? "⌘P Unpin" : "⌘P Pin"
        return (activate + [pin, "⌘⌫ Delete", "⇥ Filter"]).joined(separator: "  ")
    }

    /// "<Kind>, <preview first 100 chars>, from <App>, <relative time>[, pinned]".
    public static func rowAccessibilityLabel(_ row: ClipRow, now: Date, locale: Locale = .current) -> String {
        var parts = [kindName(row.kind), String(row.previewText.prefix(accessibilityPreviewLimit))]
        if let app = row.sourceAppName { parts.append("from \(app)") }
        parts.append(relativeTime(row.lastCopiedAt, now: now, locale: locale))
        if row.isPinned { parts.append("pinned") }
        return parts.joined(separator: ", ")
    }

    public static func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    private static func kindName(_ kind: ClipKind) -> String {
        switch kind {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .file: "Files"
        }
    }

    private static func fileCount(_ n: Int, locale: Locale) -> String {
        "\(number(n, locale: locale)) \(n == 1 ? "file" : "files")"
    }

    private static func number(_ n: Int, locale: Locale) -> String {
        n.formatted(.number.locale(locale))
    }
}
