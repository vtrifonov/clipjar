import Foundation

public enum FilterChip: CaseIterable, Sendable, Hashable {
    case all, text, links, images, files, pinned

    /// nil means any kind.
    public var kinds: Set<ClipKind>? {
        switch self {
        case .all, .pinned: nil
        case .text: [.text]
        case .links: [.link]
        case .images: [.image]
        case .files: [.file]
        }
    }
}

public struct ParsedQuery: Sendable, Equatable {
    public var terms: [String]
    public var apps: [String]
    public var kinds: Set<ClipKind>?
    public var pinnedOnly: Bool

    public init(terms: [String] = [], apps: [String] = [], kinds: Set<ClipKind>? = nil, pinnedOnly: Bool = false) {
        self.terms = terms
        self.apps = apps
        self.kinds = kinds
        self.pinnedOnly = pinnedOnly
    }
}

/// Search box syntax: whitespace-separated terms, `"quoted phrases"` (always literal), `@app`,
/// and `is:link|image|file|text|pinned`.
public enum QueryParser {
    private static let kindKeywords: [String: ClipKind] = ["link": .link, "image": .image, "file": .file, "text": .text]

    public static func parse(_ s: String) -> ParsedQuery {
        var result = ParsedQuery()
        for token in tokenize(s) {
            if token.quoted {
                result.terms.append(token.text)
                continue
            }
            let text = token.text
            if text.hasPrefix("@") {
                let app = String(text.dropFirst())
                if !app.isEmpty { result.apps.append(app) }
                continue
            }
            if text.lowercased().hasPrefix("is:") {
                let keyword = text.dropFirst(3).lowercased()
                if keyword.isEmpty { continue }
                if keyword == "pinned" {
                    result.pinnedOnly = true
                    continue
                }
                if let kind = kindKeywords[keyword] {
                    result.kinds = (result.kinds ?? []).union([kind])
                    continue
                }
            }
            result.terms.append(text)
        }
        return result
    }

    /// Token kinds intersect the chip's kinds when both are set; the result may be empty (no matches).
    public static func clipQuery(_ p: ParsedQuery, chip: FilterChip, limit: Int) -> ClipQuery {
        let kinds: Set<ClipKind>? = switch (chip.kinds, p.kinds) {
        case let (chipKinds?, tokenKinds?): chipKinds.intersection(tokenKinds)
        case let (chipKinds, tokenKinds): chipKinds ?? tokenKinds
        }
        return ClipQuery(
            terms: p.terms, apps: p.apps, kinds: kinds, pinnedOnly: p.pinnedOnly || chip == .pinned, limit: limit
        )
    }

    /// An opening quote at a token start runs to the next quote, or to the end of the input.
    private static func tokenize(_ s: String) -> [(text: String, quoted: Bool)] {
        var tokens: [(text: String, quoted: Bool)] = []
        var current = ""
        var inQuote = false
        func flush(quoted: Bool) {
            let text = quoted ? current.trimmingCharacters(in: .whitespacesAndNewlines) : current
            if !text.isEmpty { tokens.append((text, quoted)) }
            current = ""
        }
        for ch in s {
            if inQuote {
                if ch == "\"" {
                    flush(quoted: true)
                    inQuote = false
                } else {
                    current.append(ch)
                }
            } else if ch.isWhitespace {
                flush(quoted: false)
            } else if ch == "\"" && current.isEmpty {
                inQuote = true
            } else {
                current.append(ch)
            }
        }
        flush(quoted: inQuote)
        return tokens
    }
}
