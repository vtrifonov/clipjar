import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct ClipStorePruneTests {
    private let day: TimeInterval = 86_400

    private func items(_ count: Int, from start: Date = t0) -> [Clip] {
        (0..<count).map { Clip.make("Item \($0)", at: start + Double($0)) }
    }

    private func ids(_ w: any DatabaseWriter, pinned: Bool) throws -> Set<Int64> {
        try Set(w.read { try Int64.fetchAll($0, sql: "SELECT id FROM clip WHERE isPinned = ?", arguments: [pinned]) })
    }

    @Test(arguments: Backend.allCases)
    func limitExcludesPins(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let unpinned = try seed(fx.writer, items(205))
        let pinned = try seed(fx.writer, (0..<3).map { Clip.make("Pinned \($0)", at: t0 - 1000, pinned: true) })
        #expect(try await fx.store.prune(limit: .l200, maxAgeDays: 0, now: t0 + 10_000) == 5)
        #expect(try ids(fx.writer, pinned: false) == Set(unpinned.dropFirst(5)))
        #expect(try ids(fx.writer, pinned: true) == Set(pinned))
    }

    @Test(arguments: Backend.allCases)
    func ageExcludesPins(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let seeded = try seed(fx.writer, [
            Clip.make("old unpinned", at: t0 - 8 * day),
            Clip.make("old pinned", at: t0 - 8 * day, pinned: true),
            Clip.make("recent unpinned", at: t0 - 6 * day),
        ])
        #expect(try await fx.store.prune(limit: .unlimited, maxAgeDays: 7, now: t0) == 1)
        let remaining = try await fx.writer.read { try Int64.fetchAll($0, sql: "SELECT id FROM clip") }
        #expect(Set(remaining) == [seeded[1], seeded[2]])
    }

    /// Both rules prune oldest-first, so their sets nest; the age rule here reaches one row past the limit.
    @Test(arguments: Backend.allCases)
    func ageAndLimitUnion(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let old = try seed(fx.writer, [Clip.make("old a", at: t0 - 9 * day), Clip.make("old b", at: t0 - 8 * day)])
        try seed(fx.writer, items(199))
        #expect(try await fx.store.pruneCount(limit: .l200, maxAgeDays: 0, now: t0 + 1000) == 1)
        #expect(try await fx.store.pruneCount(limit: .unlimited, maxAgeDays: 7, now: t0 + 1000) == 2)
        #expect(try await fx.store.prune(limit: .l200, maxAgeDays: 7, now: t0 + 1000) == 2)
        #expect(try ids(fx.writer, pinned: false).isDisjoint(with: old))
        #expect(try clipCount(fx.writer) == 199)
    }

    @Test(arguments: Backend.allCases)
    func noopWhenUnlimitedAndAgeOff(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        try seed(fx.writer, [Clip.make("ancient", at: t0 - 400 * day)] + items(10))
        #expect(try await fx.store.prune(limit: .unlimited, maxAgeDays: 0, now: t0 + 1000) == 0)
        #expect(try clipCount(fx.writer) == 11)
    }

    @Test(arguments: Backend.allCases)
    func tieBreakById(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let tied = try seed(fx.writer, [Clip.make("tie a", at: t0 - 10), Clip.make("tie b", at: t0 - 10)])
        try seed(fx.writer, items(199))
        #expect(try await fx.store.prune(limit: .l200, maxAgeDays: 0, now: t0 + 1000) == 1)
        #expect(try fetchClip(fx.writer, tied[0]) == nil)
        #expect(try fetchClip(fx.writer, tied[1]) != nil)
    }

    @Test(arguments: Backend.allCases)
    func pruneRemovesBlobsAfterCommit(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let png = TestImages.png(width: 40, height: 30)
        let hash = ContentHash.of(imageBytes: png)
        try await fx.store.ingest(image(png), source: nil, at: t0 - 1000)
        try seed(fx.writer, items(200))
        #expect(try await fx.store.prune(limit: .l200, maxAgeDays: 0, now: t0 + 1000) == 1)
        #expect(!FileManager.default.fileExists(atPath: fx.blobsURL.appendingPathComponent("\(hash).png").path))
        #expect(!FileManager.default.fileExists(atPath: fx.blobsURL.appendingPathComponent("\(hash).thumb.png").path))
    }

    @Test(arguments: Backend.allCases)
    func prunedClipsDoNotMatchSearch(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        try seed(fx.writer, [Clip.make("Hello, Clipjar", at: t0 - 1000)] + items(200))
        #expect(try await fx.store.prune(limit: .l200, maxAgeDays: 0, now: t0 + 1000) == 1)
        #expect(try await fx.writer.read { try ClipQuery(terms: ["clipjar"]).fetchRows($0) } == [])
    }

    @Test(arguments: Backend.allCases)
    func pruneCountMatchesAndIsReadOnly(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        try seed(fx.writer, items(205))
        try seed(fx.writer, (0..<3).map { Clip.make("Pinned \($0)", at: t0 - 1000, pinned: true) })
        #expect(try await fx.store.pruneCount(limit: .l200, maxAgeDays: 0, now: t0 + 10_000) == 5)
        #expect(try clipCount(fx.writer) == 208)
        #expect(try await fx.store.prune(limit: .l200, maxAgeDays: 0, now: t0 + 10_000) == 5)
    }

    @Test(arguments: Backend.allCases)
    func ingestPrunesWithConfiguredLimit(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        await fx.store.configure(limit: .l200, maxAgeDays: 0)
        let seeded = try seed(fx.writer, items(200))
        let result = try await fx.store.ingest(text("Hello, Clipjar"), source: textEdit, at: t0 + 10_000)
        guard case let .inserted(id) = result else {
            Issue.record("expected .inserted, got \(result)")
            return
        }
        #expect(try clipCount(fx.writer) == 200)
        #expect(try fetchClip(fx.writer, seeded[0]) == nil)
        #expect(try fetchClip(fx.writer, id) != nil)
    }

    @Test(arguments: Backend.allCases)
    func defaultConfigurationIs1000(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        try seed(fx.writer, items(1000))
        try await fx.store.ingest(text("Hello, Clipjar"), source: textEdit, at: t0 + 10_000)
        #expect(try clipCount(fx.writer) == 1000)
    }

    @Test(arguments: Backend.allCases)
    func pruneErrorDoesNotFailIngest(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        await fx.store.configure(limit: .l200, maxAgeDays: 0)
        try seed(fx.writer, items(200))
        try await fx.writer.write {
            try $0.execute(sql: "CREATE TRIGGER t_fail BEFORE DELETE ON clip BEGIN SELECT RAISE(ABORT, 'test'); END")
        }
        let result = try await fx.store.ingest(text("Hello, Clipjar"), source: textEdit, at: t0 + 10_000)
        guard case .inserted = result else {
            Issue.record("expected .inserted, got \(result)")
            return
        }
        #expect(try clipCount(fx.writer) == 201)
    }
}
