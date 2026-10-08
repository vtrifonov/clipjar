import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct ClipQueryTests {
    private func migratedWriter(_ backend: Backend, _ dir: TempDir) throws -> any DatabaseWriter {
        let w = try makeWriter(backend, in: dir)
        try Schema.migrator.migrate(w)
        return w
    }

    private func ids(_ w: any DatabaseWriter, _ q: ClipQuery) throws -> [Int64] {
        try w.read { try q.fetchRows($0) }.map(\.id)
    }

    @Test(arguments: Backend.allCases)
    func substringMatchesMidWord(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let seeded = try seed(w, [Clip.make("Hello, Clipjar"), Clip.make("Something else")])
        #expect(try ids(w, ClipQuery(terms: ["lipj"])) == [seeded[0]])
    }

    @Test(arguments: Backend.allCases)
    func caseAndDiacriticFolding(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let seeded = try seed(w, [Clip.make("Café au lait"), Clip.make("Äpfel")])
        #expect(try ids(w, ClipQuery(terms: ["cafe"])) == [seeded[0]])
        #expect(try ids(w, ClipQuery(terms: ["CAFÉ"])) == [seeded[0]])
        // "ä" folds to "a", which also occurs in "Café au lait"; only assert Äpfel is found.
        #expect(try ids(w, ClipQuery(terms: ["ä"])).contains(seeded[1]))
    }

    @Test(arguments: Backend.allCases)
    func shortTermUsesEscapedLike(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let seeded = try seed(w, [Clip.make("xaby"), Clip.make("100% done"), Clip.make("a_b"), Clip.make("axb")])
        #expect(try ids(w, ClipQuery(terms: ["ab"])) == [seeded[0]])
        #expect(try ids(w, ClipQuery(terms: ["%"])) == [seeded[1]])
        #expect(try ids(w, ClipQuery(terms: ["_"])) == [seeded[2]])
    }

    @Test(arguments: Backend.allCases)
    func shortTermEscapesBackslashAndWildcards(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let seeded = try seed(w, [
            Clip.make(#"a\%b"#), Clip.make("50% off"), Clip.make(#"a\b"#), Clip.make(#"x\_y"#), Clip.make("x_y"),
        ])
        #expect(try ids(w, ClipQuery(terms: [#"\%"#])) == [seeded[0]])
        #expect(try ids(w, ClipQuery(terms: [#"\_"#])) == [seeded[3]])
        #expect(try Set(ids(w, ClipQuery(terms: [#"\"#]))) == [seeded[0], seeded[2], seeded[3]])
    }

    @Test(arguments: Backend.allCases)
    func termsAreAnded(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let seeded = try seed(w, [Clip.make("red apple"), Clip.make("red car")])
        #expect(try ids(w, ClipQuery(terms: ["red", "apple"])) == [seeded[0]])
    }

    @Test(arguments: Backend.allCases)
    func appsAreOred(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let seeded = try seed(w, [
            Clip.make("one", app: "TextEdit", bundleID: "com.apple.TextEdit"),
            Clip.make("two", app: "Safari", bundleID: "com.apple.Safari"),
            Clip.make("three", app: "Finder", bundleID: "com.apple.finder"),
        ])
        #expect(try ids(w, ClipQuery(apps: ["textedit", "safari"])).sorted() == [seeded[0], seeded[1]])
        #expect(try ids(w, ClipQuery(apps: ["apple.saf"])) == [seeded[1]])
    }

    @Test(arguments: Backend.allCases)
    func kindsFilter(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let seeded = try seed(w, [Clip.make("plain words"), Clip.make("https://example.com", kind: .link)])
        #expect(try ids(w, ClipQuery(kinds: [.link])) == [seeded[1]])
        let empty = ClipQuery(kinds: [])
        #expect(try ids(w, empty) == [])
        #expect(try w.read { try empty.fetchCount($0) } == 0)
    }

    @Test(arguments: Backend.allCases)
    func pinnedOnly(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let seeded = try seed(w, [Clip.make("loose"), Clip.make("fixed", pinned: true)])
        #expect(try ids(w, ClipQuery(pinnedOnly: true)) == [seeded[1]])
    }

    @Test(arguments: Backend.allCases)
    func orderIsRecencyThenIdNotPinned(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let later = t0.addingTimeInterval(60)
        let seeded = try seed(w, [
            Clip.make("old pinned", at: t0, pinned: true),
            Clip.make("same time first", at: later),
            Clip.make("same time second", at: later),
        ])
        #expect(try ids(w, .all) == [seeded[2], seeded[1], seeded[0]])
    }

    @Test(arguments: Backend.allCases)
    func limitAndCount(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let clips = (0..<5).map { Clip.make("clip number \($0)", at: t0.addingTimeInterval(Double($0))) }
        let seeded = try seed(w, clips)
        let q = ClipQuery(limit: 2)
        #expect(try ids(w, q) == [seeded[4], seeded[3]])
        #expect(try w.read { try q.fetchCount($0) } == 5)
    }

    @Test(arguments: Backend.allCases)
    func fileCountProjected(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        var files = Clip.make("/tmp/a.txt\n/tmp/b.txt\n/tmp/c.txt", kind: .file)
        files.fileURLs = ["file:///tmp/a.txt", "file:///tmp/b.txt", "file:///tmp/c.txt"]
        let seeded = try seed(w, [files, Clip.make("plain words", at: t0.addingTimeInterval(1))])
        let rows = try w.read { try ClipQuery.all.fetchRows($0) }
        #expect(rows.first { $0.id == seeded[0] }?.fileCount == 3)
        #expect(rows.first { $0.id == seeded[1] }?.fileCount == 0)
    }

    @Test(arguments: Backend.allCases)
    func ftsSyntaxIsLiteral(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try migratedWriter(backend, dir)
        let seeded = try seed(w, [Clip.make("say (xyz) now")])
        for term in ["a\"b\"c", "NEAR(x", "*foo*", "-bar", "(xyz)", "OR", "AND"] {
            _ = try ids(w, ClipQuery(terms: [term]))
        }
        #expect(try ids(w, ClipQuery(terms: ["(xyz)"])) == [seeded[0]])
    }
}
