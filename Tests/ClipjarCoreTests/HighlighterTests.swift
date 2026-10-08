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

    @Test func capAppliesAcrossTermsInTextOrder() {
        let ranges = substrings(["b", "a"], in: String(repeating: "a b ", count: 100))
        #expect(ranges.count == 50)
        #expect(ranges.prefix(4) == ["a", "b", "a", "b"])
    }

    /// Matches dropped as overlaps must not use up the cap: a long term covering many short-term
    /// matches still leaves later short-term matches eligible.
    @Test func overlapsDoNotConsumeCap() {
        let text = String(repeating: "x", count: 60) + " " + String(repeating: "x ", count: 10)
        let ranges = Highlighter.ranges(of: ["x", String(repeating: "x", count: 60)], in: text, max: 5)
        #expect(ranges.count == 5)
        #expect(String(text[ranges[0]]).count == 60)
    }

    /// ~5M matches in a 10 MB text: only the first 50 may be searched for, so this stays fast.
    @Test func largeInputStopsAtCap() {
        let text = String(repeating: "e ", count: 5_000_000)
        let start = ContinuousClock.now
        let ranges = Highlighter.ranges(of: ["e"], in: text)
        let elapsed = ContinuousClock.now - start
        #expect(ranges.count == 50)
        #expect(text.distance(from: text.startIndex, to: ranges[49].lowerBound) == 98)
        #expect(elapsed < .milliseconds(500), "took \(elapsed)")
    }

    @Test func emptyTerms() {
        #expect(Highlighter.ranges(of: [], in: "Hello, Clipjar").isEmpty)
        #expect(Highlighter.ranges(of: [""], in: "Hello, Clipjar").isEmpty)
    }

    @Test func emojiTextRangesValid() {
        #expect(substrings(["family"], in: "👩‍👩‍👧 family") == ["family"])
    }
}
