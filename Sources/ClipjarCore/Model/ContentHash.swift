import CryptoKit
import Foundation

public enum ContentHash {
    /// "\r\n" and "\r" become "\n"; nothing else changes.
    public static func normalisedText(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    public static func of(kind: ClipKind, plainText: String) -> String {
        hash(kind: kind, content: Data(normalisedText(plainText).utf8))
    }

    public static func of(imageBytes: Data) -> String {
        hash(kind: .image, content: imageBytes)
    }

    public static func of(fileURLs: [URL]) -> String {
        hash(kind: .file, content: Data(fileURLs.map(\.absoluteString).joined(separator: "\n").utf8))
    }

    public static func of(_ c: CapturedContent) -> String {
        switch c.kind {
        case .text, .link: of(kind: c.kind, plainText: c.plainText)
        case .image: of(imageBytes: c.image?.data ?? Data())
        case .file: of(fileURLs: c.fileURLs)
        }
    }

    private static func hash(kind: ClipKind, content: Data) -> String {
        var input = Data(kind.rawValue.utf8)
        input.append(0x00)
        input.append(content)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}
