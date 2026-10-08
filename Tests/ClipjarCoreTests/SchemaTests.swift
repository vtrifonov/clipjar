import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct SchemaTests {
    @Test(arguments: Backend.allCases)
    func migratorCreatesSchema(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try makeWriter(backend, in: dir)
        try Schema.migrator.migrate(w)
        let (hasClip, hasFTS) = try w.read { db in
            (try db.tableExists("clip"), try db.tableExists("clip_fts"))
        }
        #expect(hasClip)
        #expect(hasFTS)
    }

    @Test(arguments: Backend.allCases)
    func migrationsIdempotent(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try makeWriter(backend, in: dir)
        try Schema.migrator.migrate(w)
        try Schema.migrator.migrate(w)
        let applied = try w.read { try Schema.migrator.appliedMigrations($0) }
        #expect(applied == ["v1"])
    }

    @Test(arguments: Backend.allCases)
    func clipRoundTrip(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try makeWriter(backend, in: dir)
        try Schema.migrator.migrate(w)
        var clip = Clip.make("Hello, Clipjar")
        clip.fileURLs = ["file:///tmp/a%20b.txt"]
        clip.rtfData = Data([1, 2])
        let inserted = try w.write { db -> Clip in
            var c = clip
            try c.insert(db)
            return c
        }
        let id = try #require(inserted.id)
        let fetched = try w.read { try Clip.fetchOne($0, key: id) }
        #expect(fetched == inserted)
    }

    @Test(arguments: Backend.allCases)
    func ftsTriggersTrackInsertUpdateDelete(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try makeWriter(backend, in: dir)
        try Schema.migrator.migrate(w)
        let id = try seed(w, [Clip.make("hello clipjar")])[0]

        func matches(_ db: Database, _ term: String) throws -> [Int64] {
            try Int64.fetchAll(db, sql: "SELECT rowid FROM clip_fts WHERE clip_fts MATCH ?", arguments: ["\"\(term)\""])
        }

        #expect(try w.read { try matches($0, "lipj") } == [id])

        try w.write { db in
            try db.execute(sql: "UPDATE clip SET searchText = ? WHERE id = ?", arguments: ["other words", id])
        }
        #expect(try w.read { try matches($0, "lipj") }.isEmpty)
        #expect(try w.read { try matches($0, "word") } == [id])

        try w.write { db in
            try db.execute(sql: "DELETE FROM clip WHERE id = ?", arguments: [id])
        }
        #expect(try w.read { try matches($0, "word") }.isEmpty)
    }

    @Test(arguments: Backend.allCases)
    func contentHashIsUnique(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try makeWriter(backend, in: dir)
        try Schema.migrator.migrate(w)
        try seed(w, [Clip.make("Hello, Clipjar")])
        do {
            try seed(w, [Clip.make("Hello, Clipjar")])
            Issue.record("expected a unique constraint violation")
        } catch let error as DatabaseError {
            #expect(error.resultCode == .SQLITE_CONSTRAINT)
        }
    }

    @Test(arguments: Backend.allCases)
    func kindCheckRejectsUnknown(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try makeWriter(backend, in: dir)
        try Schema.migrator.migrate(w)
        #expect(throws: DatabaseError.self) {
            try w.write { db in
                try db.execute(sql: """
                    INSERT INTO clip (kind, contentHash, createdAt, lastCopiedAt)
                    VALUES ('video', 'h', '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                    """)
            }
        }
    }

    @Test(arguments: Backend.allCases)
    func secureDeleteIsOn(_ backend: Backend) throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let w = try makeWriter(backend, in: dir)
        try Schema.migrator.migrate(w)
        let value = try w.read { try Int.fetchOne($0, sql: "PRAGMA secure_delete") }
        #expect(value == 1)
    }
}
