import Foundation
import Testing
@testable import ClipjarCore

@Suite struct ContentHashTests {
    @Test func isLowercaseHex64() {
        let h = ContentHash.of(kind: .text, plainText: "Hello, Clipjar")
        #expect(h.count == 64 && h == h.lowercased() && h.allSatisfy(\.isHexDigit))
    }

    @Test func crlfAndCrNormalised() {
        #expect(ContentHash.of(kind: .text, plainText: "a\r\nb") == ContentHash.of(kind: .text, plainText: "a\nb"))
        #expect(ContentHash.of(kind: .text, plainText: "a\rb") == ContentHash.of(kind: .text, plainText: "a\nb"))
    }

    @Test func trailingNewlineDistinct() {
        #expect(ContentHash.of(kind: .text, plainText: "echo hi") != ContentHash.of(kind: .text, plainText: "echo hi\n"))
    }

    @Test func kindIsPartOfHash() {
        #expect(ContentHash.of(kind: .text, plainText: "https://example.com")
            != ContentHash.of(kind: .link, plainText: "https://example.com"))
    }

    @Test func richDataNotHashed() {
        let a = CapturedContent(kind: .text, plainText: "Hello, Clipjar", rtf: Data([1, 2]), html: nil)
        let b = CapturedContent(kind: .text, plainText: "Hello, Clipjar", rtf: Data([3]), html: Data([4, 5]))
        #expect(ContentHash.of(a) == ContentHash.of(b))
    }

    @Test func fileOrderMatters() {
        let a = URL(fileURLWithPath: "/tmp/a.txt")
        let b = URL(fileURLWithPath: "/tmp/b.txt")
        #expect(ContentHash.of(fileURLs: [a, b]) != ContentHash.of(fileURLs: [b, a]))
    }

    @Test func imageHashUsesBytes() {
        let bytes = Data([1, 2, 3, 4])
        #expect(ContentHash.of(imageBytes: bytes) == ContentHash.of(imageBytes: Data([1, 2, 3, 4])))
        #expect(ContentHash.of(imageBytes: bytes) != ContentHash.of(imageBytes: Data([1, 2, 3, 5])))
    }
}
