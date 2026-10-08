import Testing
@testable import ClipjarCore

@Suite struct HighlighterTests {
    private func substrings(_ terms: [String], in text: String, max: Int = 50) -> [String] {
        Highlighter.ranges(of: terms, in: text, max: max).map { String(text[$0]) }
    }

    @Test func findsCaseInsensitive() {
        #expect(substrings(["clip"], in: "Hello, Clipjar") == ["Clip"])
    }

    @Test func diacriticInsensitive() {
        #expect(substrings(["cafe"], in: "Café") == ["Café"])
    }

    @Test func multipleTermsSorted() {
        #expect(substrings(["apple", "red"], in: "red apple red") == ["red", "apple", "red"])
    }

    @Test func overlapsDropped() {
        #expect(substrings(["abc", "bcd"], in: "abcd") == ["abc"])
    }

    @Test func equalStartLongerWins() {
        #expect(substrings(["ab", "abc"], in: "abcd") == ["abc"])
    }

    @Test func capAt50() {
        #expect(Highlighter.ranges(of: ["a"], in: String(repeating: "a ", count: 100)).count == 50)
    }

    @Test func emptyTerms() {
        #expect(Highlighter.ranges(of: [], in: "Hello, Clipjar").isEmpty)
        #expect(Highlighter.ranges(of: [""], in: "Hello, Clipjar").isEmpty)
    }

    @Test func emojiTextRangesValid() {
        #expect(substrings(["family"], in: "👩‍👩‍👧 family") == ["family"])
    }
}
