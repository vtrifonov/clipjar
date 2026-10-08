import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct StoreOpenerRecoveryTests {
    private let stamp = "20261008-101500"
    private let now = Calendar.current.date(
        from: DateComponents(year: 2026, month: 10, day: 8, hour: 10, minute: 15, second: 0)
    )!

    private func supportURL(_ dir: TempDir) -> URL {
        dir.url.appendingPathComponent("Support", isDirectory: true)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Garbage database, WAL, SHM and one blob file.
    private func writeGarbageStore(at support: URL) throws {
        let blobs = support.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        let garbage = Data(String(repeating: "not a database", count: 600).utf8.prefix(8192))
        try garbage.write(to: support.appendingPathComponent("clips.sqlite"))
        try garbage.write(to: support.appendingPathComponent("clips.sqlite-wal"))
        try garbage.write(to: support.appendingPathComponent("clips.sqlite-shm"))
        try Data("synthetic".utf8).write(to: blobs.appendingPathComponent("x.png"))
    }

    private func createFlag(in support: URL) throws {
        try Data().write(to: support.appendingPathComponent(StoreOpener.repairFlagName))
    }

    @Test func garbageDatabaseIsMovedAside() async throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        try writeGarbageStore(at: support)
        let r = await StoreOpener.open(supportDirectory: support, now: now)
        defer { try? r.store.close() }
        #expect(r.recoveredFromCorruption)
        #expect(!r.storageUnavailable)
        #expect(r.supportDirectory == support)
        let moved = "clips.sqlite.corrupt-\(stamp)"
        #expect(exists(support.appendingPathComponent(moved)))
        #expect(exists(support.appendingPathComponent(moved + "-wal")))
        #expect(exists(support.appendingPathComponent(moved + "-shm")))
        #expect(exists(support.appendingPathComponent("blobs.corrupt-\(stamp)/x.png")))
        #expect(!exists(support.appendingPathComponent("blobs/x.png")))
        let result = try await r.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
        guard case let .inserted(id) = result else {
            Issue.record("expected .inserted, got \(result)")
            return
        }
        #expect(try await r.store.clip(id: id)?.plainText == "Hello, Clipjar")
    }

    @Test func stampCollisionGetsSuffix() async throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        try writeGarbageStore(at: support)
        let existing = support.appendingPathComponent("clips.sqlite.corrupt-\(stamp)")
        try Data("earlier".utf8).write(to: existing)
        let r = await StoreOpener.open(supportDirectory: support, now: now)
        defer { try? r.store.close() }
        #expect(r.recoveredFromCorruption)
        #expect(try Data(contentsOf: existing) == Data("earlier".utf8))
        #expect(exists(support.appendingPathComponent("clips.sqlite.corrupt-\(stamp)-2")))
        #expect(exists(support.appendingPathComponent("blobs.corrupt-\(stamp)-2/x.png")))
    }

    @Test func repairFlagRepairsTamperedFTS() async throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        let first = await StoreOpener.open(supportDirectory: support, now: now)
        try await first.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
        try first.store.close()
        // The system SQLite runs in defensive mode, so the FTS shadow tables can't be written directly;
        // drop the row's index entry through FTS5's 'delete' command instead, leaving the content row.
        let raw = try DatabaseQueue(path: support.appendingPathComponent("clips.sqlite").path)
        try await raw.write {
            try $0.execute(sql: """
                INSERT INTO clip_fts(clip_fts, rowid, searchText) SELECT 'delete', id, searchText FROM clip
                """)
        }
        #expect(try await raw.read { try ClipQuery(terms: ["clipjar"]).fetchCount($0) } == 0)
        try raw.close()
        try createFlag(in: support)

        let r = await StoreOpener.open(supportDirectory: support, now: now)
        defer { try? r.store.close() }
        #expect(!r.recoveredFromCorruption)
        #expect(r.ranRepairChecks)
        #expect(!r.storageUnavailable)
        #expect(!exists(support.appendingPathComponent(StoreOpener.repairFlagName)))
        #expect(try await r.store.reader.read { try ClipQuery(terms: ["clipjar"]).fetchCount($0) } == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: support.path)
        #expect(!names.contains { $0.contains(".corrupt-") })
    }

    @Test func flagOnHealthyDatabaseIsCleared() async throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        let first = await StoreOpener.open(supportDirectory: support, now: now)
        try first.store.close()
        try createFlag(in: support)
        let r = await StoreOpener.open(supportDirectory: support, now: now)
        defer { try? r.store.close() }
        #expect(r.ranRepairChecks)
        #expect(!r.recoveredFromCorruption)
        #expect(!exists(support.appendingPathComponent(StoreOpener.repairFlagName)))
    }

    /// A healthy on-disk store holding one clip, with the repair flag set.
    private func flaggedStore(_ dir: TempDir) async throws -> URL {
        let support = supportURL(dir)
        let first = await StoreOpener.open(supportDirectory: support, now: now)
        try await first.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
        try first.store.close()
        try createFlag(in: support)
        return support
    }

    private func expectMovedAside(_ r: OpenResult, _ support: URL) throws {
        #expect(r.recoveredFromCorruption)
        #expect(r.ranRepairChecks)
        #expect(!r.storageUnavailable)
        #expect(exists(support.appendingPathComponent("clips.sqlite.corrupt-\(stamp)")))
        #expect(!exists(support.appendingPathComponent(StoreOpener.repairFlagName)))
    }

    @Test func failingChecksMoveAside() async throws {
        let dir = try TempDir()
        let support = try await flaggedStore(dir)
        let r = await StoreOpener.open(supportDirectory: support, now: now, repairChecks: { _ in false })
        defer { try? r.store.close() }
        try expectMovedAside(r, support)
    }

    @Test(arguments: [DatabaseError.SQLITE_CORRUPT, .SQLITE_NOTADB, .SQLITE_CONSTRAINT])
    func checkErrorMovesAside(_ code: ResultCode) async throws {
        let dir = try TempDir()
        let support = try await flaggedStore(dir)
        let r = await StoreOpener.open(
            supportDirectory: support, now: now, repairChecks: { _ in throw DatabaseError(resultCode: code) }
        )
        defer { try? r.store.close() }
        try expectMovedAside(r, support)
    }

    @Test(arguments: [DatabaseError.SQLITE_FULL, .SQLITE_IOERR, .SQLITE_BUSY, .SQLITE_NOMEM, .SQLITE_CANTOPEN])
    func transientCheckErrorKeepsFlagAndUsesMemory(_ code: ResultCode) async throws {
        let dir = try TempDir()
        let support = try await flaggedStore(dir)
        let r = await StoreOpener.open(
            supportDirectory: support, now: now, repairChecks: { _ in throw DatabaseError(resultCode: code) }
        )
        #expect(r.storageUnavailable)
        #expect(!r.recoveredFromCorruption)
        #expect(exists(support.appendingPathComponent(StoreOpener.repairFlagName)))
        #expect(exists(support.appendingPathComponent("clips.sqlite")))
        let names = try FileManager.default.contentsOfDirectory(atPath: support.path)
        #expect(!names.contains { $0.contains(".corrupt-") })
    }

    @Test(arguments: ["clips.sqlite-wal", "clips.sqlite-shm", "blobs"])
    func failedRenameRollsBackMoveAside(_ failing: String) throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        try writeGarbageStore(at: support)
        #expect(throws: CocoaError.self) {
            try StoreOpener.moveAside(support, now: now) { source, target in
                if source.lastPathComponent == failing { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.moveItem(at: source, to: target)
            }
        }
        for name in ["clips.sqlite", "clips.sqlite-wal", "clips.sqlite-shm", "blobs/x.png"] {
            #expect(exists(support.appendingPathComponent(name)), "\(name) restored")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: support.path)
        #expect(!names.contains { $0.contains(".corrupt-") })
    }

    @Test func noFlagSkipsChecks() async throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        let first = await StoreOpener.open(supportDirectory: support, now: now)
        try first.store.close()
        let r = await StoreOpener.open(supportDirectory: support, now: now)
        defer { try? r.store.close() }
        #expect(!r.ranRepairChecks)
        #expect(!r.recoveredFromCorruption)
    }
}
