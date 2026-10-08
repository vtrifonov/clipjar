import Foundation

public enum TextHeuristics {
    public static let previewLimit = 300
    private static let maxLinkLength = 2_048
    private static let codeMarkers = ["{", "};", "=>", "</", "#include", "func ", "def "]

    /// Whitespace runs collapse to one space, the result is trimmed and cut at `previewLimit`
    /// Characters. Scanning stops as soon as the limit is reached.
    public static func previewText(_ s: String) -> String {
        var out = ""
        var count = 0
        var pendingSpace = false
        for ch in s {
            if ch.isWhitespace {
                pendingSpace = count > 0
                continue
            }
            if pendingSpace {
                out.append(" ")
                count += 1
                pendingSpace = false
                if count >= previewLimit { break }
            }
            out.append(ch)
            count += 1
            if count >= previewLimit { break }
        }
        return out
    }

    public static func isLink(_ s: String) -> Bool {
        url(from: s) != nil
    }

    public static func linkDomain(_ s: String) -> String? {
        guard let host = url(from: s)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public struct RGBA: Sendable, Equatable {
        public var r, g, b, a: Double
    }

    public static func hexColor(_ s: String) -> RGBA? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.allSatisfy(\.isHexDigit), t.allSatisfy(\.isASCII) else { return nil }
        let digits = Array(t)
        let expanded: [Character]
        switch digits.count {
        case 3: expanded = digits.flatMap { [$0, $0] }
        case 6, 8: expanded = digits
        default: return nil
        }
        func byte(_ i: Int) -> Double {
            Double(UInt8(String(expanded[i * 2 ... i * 2 + 1]), radix: 16) ?? 0) / 255
        }
        return RGBA(r: byte(0), g: byte(1), b: byte(2), a: expanded.count == 8 ? byte(3) : 1)
    }

    public static func isCodeLike(_ s: String) -> Bool {
        if codeMarkers.contains(where: { s.contains($0) }) { return true }
        let lines = s.components(separatedBy: .newlines)
        return lines.count >= 2 && lines.contains { $0.hasPrefix("\t") || $0.hasPrefix("    ") }
    }

    private static func url(from s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= maxLinkLength, !t.contains(where: \.isWhitespace) else { return nil }
        if let u = URL(string: t), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return (u.host ?? "").isEmpty ? nil : u
        }
        if t.lowercased().hasPrefix("www."), let u = URL(string: "https://" + t),
           let host = u.host, host.contains(".") {
            return u
        }
        return nil
    }
}
