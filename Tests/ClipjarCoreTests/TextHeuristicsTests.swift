import Foundation
import Testing
@testable import ClipjarCore

@Suite struct TextHeuristicsTests {
    @Test func previewCollapsesWhitespace() {
        #expect(TextHeuristics.previewText("  Hello,\n\n\tClipjar  ") == "Hello, Clipjar")
    }

    @Test func previewCutsAt300Characters() {
        #expect(TextHeuristics.previewText(String(repeating: "a", count: 1_000)).count == 300)
    }

    @Test func previewIsGraphemeSafe() {
        let family = "👩‍👩‍👧"
        let s = String(repeating: "a", count: 299) + family + "bbb"
        let p = TextHeuristics.previewText(s)
        #expect(p.count == 300)
        #expect(p.hasSuffix(family))
    }

    @Test func previewOfOneMegabyteIsFast() {
        #expect(TextHeuristics.previewText(String(repeating: "x", count: 1_000_000)).count == 300)
    }

    @Test(arguments: [
        ("https://example.com/docs", true),
        ("http://example.com", true),
        ("www.example.com", true),
        ("  https://example.com  ", true),
        ("foo bar.com", false),
        ("mailto:hello@example.com", false),
        ("https://", false),
        ("ftp://example.com", false),
        ("example.com", false),
        ("https://example.com/" + String(repeating: "a", count: 2_048), false),
    ])
    func isLink(text: String, expected: Bool) {
        #expect(TextHeuristics.isLink(text) == expected)
    }

    @Test func linkDomainStripsWWW() {
        #expect(TextHeuristics.linkDomain("https://www.example.com/a") == "example.com")
        #expect(TextHeuristics.linkDomain("www.example.com") == "example.com")
        #expect(TextHeuristics.linkDomain("not a link") == nil)
        #expect(TextHeuristics.linkDomain("https://WWW.Example.com/a") == "example.com")
        #expect(TextHeuristics.linkDomain("WWW.Example.com") == "example.com")
    }

    @Test(arguments: [
        ("#FF8800", 1.0, 0.5333, 0.0, 1.0),
        ("F80", 1.0, 0.5333, 0.0, 1.0),
        ("#FF880080", 1.0, 0.5333, 0.0, 0.502),
    ])
    func hexColor(text: String, r: Double, g: Double, b: Double, a: Double) throws {
        let c = try #require(TextHeuristics.hexColor(text))
        #expect(abs(c.r - r) < 0.001)
        #expect(abs(c.g - g) < 0.001)
        #expect(abs(c.b - b) < 0.001)
        #expect(abs(c.a - a) < 0.001)
    }

    @Test func hexColorShortEqualsLong() {
        #expect(TextHeuristics.hexColor("F80") == TextHeuristics.hexColor("#FF8800"))
    }

    @Test(arguments: ["#FF88", "#GG8800", "FF 8800", ""])
    func hexColorInvalid(text: String) {
        #expect(TextHeuristics.hexColor(text) == nil)
    }

    @Test(arguments: [
        ("func greet() {", true),
        ("a => b", true),
        ("</div>", true),
        ("#include <stdio.h>", true),
        ("def run():", true),
        ("x\n    y", true),
        ("x\n\ty", true),
        ("Hello, world", false),
        ("    single", false),
    ])
    func isCodeLike(text: String, expected: Bool) {
        #expect(TextHeuristics.isCodeLike(text) == expected)
    }
}
