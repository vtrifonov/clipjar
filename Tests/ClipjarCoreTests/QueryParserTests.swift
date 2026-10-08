import Testing
@testable import ClipjarCore

@Suite struct QueryParserTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let input: String
        let expected: ParsedQuery
        var testDescription: String { input }
    }

    static let cases: [Case] = [
        Case(input: "hello world", expected: ParsedQuery(terms: ["hello", "world"])),
        Case(input: "\"hello world\" x", expected: ParsedQuery(terms: ["hello world", "x"])),
        Case(input: "\"open", expected: ParsedQuery(terms: ["open"])),
        Case(input: "@Safari foo", expected: ParsedQuery(terms: ["foo"], apps: ["Safari"])),
        Case(input: "@a @b", expected: ParsedQuery(apps: ["a", "b"])),
        Case(input: "is:link", expected: ParsedQuery(kinds: [.link])),
        Case(input: "IS:Image", expected: ParsedQuery(kinds: [.image])),
        Case(input: "is:file", expected: ParsedQuery(kinds: [.file])),
        Case(input: "is:text", expected: ParsedQuery(kinds: [.text])),
        Case(input: "is:link is:image", expected: ParsedQuery(kinds: [.link, .image])),
        Case(input: "is:pinned", expected: ParsedQuery(pinnedOnly: true)),
        Case(input: "is:foo", expected: ParsedQuery(terms: ["is:foo"])),
        Case(input: "@ is: x", expected: ParsedQuery(terms: ["x"])),
        Case(input: "\"@x\"", expected: ParsedQuery(terms: ["@x"])),
        Case(input: "  \t ", expected: ParsedQuery()),
    ]

    @Test(arguments: cases)
    func parses(_ c: Case) {
        #expect(QueryParser.parse(c.input) == c.expected)
    }

    @Test func chipCombination() {
        let image = QueryParser.parse("is:image")
        let none = QueryParser.parse("")
        #expect(QueryParser.clipQuery(image, chip: .links, limit: 50).kinds == [])
        #expect(QueryParser.clipQuery(none, chip: .links, limit: 50).kinds == [.link])
        #expect(QueryParser.clipQuery(QueryParser.parse("is:file"), chip: .all, limit: 50).kinds == [.file])
        let pinned = QueryParser.clipQuery(none, chip: .pinned, limit: 50)
        #expect(pinned.pinnedOnly)
        #expect(pinned.kinds == nil)
        #expect(QueryParser.clipQuery(none, chip: .all, limit: 37).limit == 37)
        let full = QueryParser.clipQuery(QueryParser.parse("@Safari foo is:pinned"), chip: .all, limit: 10)
        #expect(full == ClipQuery(terms: ["foo"], apps: ["Safari"], kinds: nil, pinnedOnly: true, limit: 10))
    }

    @Test func chipKinds() {
        #expect(FilterChip.all.kinds == nil)
        #expect(FilterChip.pinned.kinds == nil)
        #expect(FilterChip.text.kinds == [.text])
        #expect(FilterChip.links.kinds == [.link])
        #expect(FilterChip.images.kinds == [.image])
        #expect(FilterChip.files.kinds == [.file])
    }
}
