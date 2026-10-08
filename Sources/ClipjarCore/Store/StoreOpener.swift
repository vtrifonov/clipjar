import Foundation
import GRDB

public struct OpenResult: Sendable {
    public let store: ClipStore
    public let recoveredFromCorruption: Bool
    /// In-memory fallback in use.
    public let storageUnavailable: Bool
    /// True only when the `.needs-repair` flag was processed.
    public let ranRepairChecks: Bool
    /// nil for in-memory.
    public let supportDirectory: URL?
}

public enum StoreOpener {
    public static let databaseName = "clips.sqlite"
    public static let repairFlagName = ".needs-repair"
    static let blobsName = "blobs"

    public static func defaultSupportDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Clipjar", isDirectory: true)
    }

    /// A corrupt database (at open, or failing the checks run when the repair flag exists) is moved aside
    /// and replaced with a fresh one. Any other failure falls back to `openInMemory()`.
    public static func open(supportDirectory: URL, now: Date = Date()) async -> OpenResult {
        await open(supportDirectory: supportDirectory, now: now, repairChecks: runRepairChecks)
    }

    /// Test seam for the repair checks.
    static func open(
        supportDirectory: URL, now: Date, repairChecks: (any DatabaseWriter) throws -> Bool
    ) async -> OpenResult {
        let store: ClipStore
        do {
            try prepareLayout(supportDirectory)
            store = try openStore(supportDirectory)
        } catch where isCorruptDatabase(error) {
            logFailure("store is corrupt", error)
            return recover(supportDirectory, now: now, ranRepairChecks: false)
        } catch {
            logFailure("store open failed", error)
            return openInMemory()
        }

        let flag = supportDirectory.appendingPathComponent(repairFlagName)
        guard FileManager.default.fileExists(atPath: flag.path) else {
            return OpenResult(
                store: store, recoveredFromCorruption: false, storageUnavailable: false,
                ranRepairChecks: false, supportDirectory: supportDirectory
            )
        }
        do {
            if try repairChecks(store.writer) {
                removeRepairFlag(in: supportDirectory)
                return OpenResult(
                    store: store, recoveredFromCorruption: false, storageUnavailable: false,
                    ranRepairChecks: true, supportDirectory: supportDirectory
                )
            }
            Log.store.error("integrity check failed")
        } catch where isTransientFailure(error) {
            // The flag stays, so the checks run again at the next launch.
            logFailure("repair checks failed", error)
            try? store.close()
            return openInMemory()
        } catch {
            // Corruption, or a check the database itself fails (e.g. a UNIQUE violation from REINDEX).
            logFailure("repair checks found damage", error)
        }
        do {
            try store.close()
        } catch {
            logFailure("store close failed", error)
        }
        return recover(supportDirectory, now: now, ranRepairChecks: true)
    }

    public static func openInMemory() -> OpenResult {
        let blobsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clipjar-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: blobsURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        } catch {
            // BlobFiles recreates the directory on first write; image ingests fail cleanly if it can't.
            logFailure("in-memory blobs directory failed", error)
        }
        let store: ClipStore
        do {
            store = try ClipStore(writer: DatabaseQueue(configuration: Schema.configuration()), blobsDirectory: blobsURL)
        } catch {
            // An in-memory SQLite database only fails to open when the process is out of memory.
            fatalError("in-memory store failed: \((error as NSError).code)")
        }
        return OpenResult(
            store: store, recoveredFromCorruption: false, storageUnavailable: true,
            ranRepairChecks: false, supportDirectory: nil
        )
    }

    /// Support dir and `blobs/` are 0700, existing db/`-wal`/`-shm` files 0600, and the support dir is
    /// excluded from backup, all re-applied on every launch; a missing database file is created empty
    /// with 0600 before the pool opens it. A backup-exclusion failure is logged, not fatal.
    static func prepareLayout(_ supportDirectory: URL) throws {
        let fm = FileManager.default
        let blobsURL = supportDirectory.appendingPathComponent(blobsName, isDirectory: true)
        for dir in [supportDirectory, blobsURL] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        let dbPath = supportDirectory.appendingPathComponent(databaseName).path
        if !fm.fileExists(atPath: dbPath) {
            guard fm.createFile(atPath: dbPath, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        for path in [dbPath, dbPath + "-wal", dbPath + "-shm"] where fm.fileExists(atPath: path) {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = supportDirectory
        do {
            try url.setResourceValues(values)
        } catch {
            logFailure("backup exclusion failed", error)
        }
    }

    /// Opens the pool and runs the migrator; the pool is closed if the store can't be built.
    static func openStore(_ supportDirectory: URL) throws -> ClipStore {
        let pool = try DatabasePool(
            path: supportDirectory.appendingPathComponent(databaseName).path,
            configuration: Schema.configuration()
        )
        do {
            return try ClipStore(
                writer: pool, blobsDirectory: supportDirectory.appendingPathComponent(blobsName, isDirectory: true)
            )
        } catch {
            try? pool.close()
            throw error
        }
    }

    static func isCorruptDatabase(_ error: any Error) -> Bool {
        guard let code = (error as? DatabaseError)?.resultCode else { return false }
        return code == .SQLITE_CORRUPT || code == .SQLITE_NOTADB
    }

    /// Resource or environment failures that say nothing about the database's health; any other
    /// SQLite error counts as damage. Non-SQLite errors are treated as transient.
    static func isTransientFailure(_ error: any Error) -> Bool {
        guard let code = (error as? DatabaseError)?.resultCode else { return true }
        let transient: [ResultCode] = [
            .SQLITE_FULL, .SQLITE_IOERR, .SQLITE_BUSY, .SQLITE_LOCKED, .SQLITE_NOMEM, .SQLITE_CANTOPEN,
            .SQLITE_READONLY, .SQLITE_PERM, .SQLITE_AUTH, .SQLITE_INTERRUPT, .SQLITE_ABORT,
        ]
        return transient.contains(code)
    }

    /// FTS integrity check against the content table (rebuild on failure), REINDEX, then
    /// `PRAGMA integrity_check`. True iff the database is healthy afterwards.
    static func runRepairChecks(_ writer: any DatabaseWriter) throws -> Bool {
        do {
            try writer.write { try $0.execute(sql: "INSERT INTO clip_fts(clip_fts, rank) VALUES('integrity-check', 1)") }
        } catch {
            logFailure("fts integrity check failed", error)
            try writer.write { try $0.execute(sql: "INSERT INTO clip_fts(clip_fts) VALUES('rebuild')") }
        }
        return try writer.write { db in
            try db.execute(sql: "REINDEX")
            return try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok"
        }
    }

    /// Moves the database files and blobs aside (nothing is deleted), then opens a fresh store.
    /// A failed rename or fresh open falls back to `openInMemory()`.
    static func recover(_ supportDirectory: URL, now: Date, ranRepairChecks: Bool) -> OpenResult {
        do {
            try moveAside(supportDirectory, now: now)
            try prepareLayout(supportDirectory)
            let store = try openStore(supportDirectory)
            // The flag described the database that was just moved aside.
            removeRepairFlag(in: supportDirectory)
            return OpenResult(
                store: store, recoveredFromCorruption: true, storageUnavailable: false,
                ranRepairChecks: ranRepairChecks, supportDirectory: supportDirectory
            )
        } catch {
            logFailure("store recovery failed", error)
            return openInMemory()
        }
    }

    /// Renames `clips.sqlite` (+ `-wal`/`-shm`) to `clips.sqlite.corrupt-<stamp><suffix>` and `blobs/` to
    /// `blobs.corrupt-<stamp><suffix>`, with the first suffix ("", "-2", "-3", …) free for both.
    /// All or nothing: if any rename fails, the ones already done are renamed back before rethrowing,
    /// so the database is never split from its `-wal` or `blobs/`. `rename` is a test seam.
    static func moveAside(
        _ supportDirectory: URL, now: Date,
        rename: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) throws {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)

        var n = 1
        var dbTarget: String
        var blobsTarget: URL
        repeat {
            let suffix = n == 1 ? "" : "-\(n)"
            dbTarget = supportDirectory.appendingPathComponent("\(databaseName).corrupt-\(stamp)\(suffix)").path
            blobsTarget = supportDirectory.appendingPathComponent("\(blobsName).corrupt-\(stamp)\(suffix)")
            n += 1
        } while fm.fileExists(atPath: dbTarget) || fm.fileExists(atPath: blobsTarget.path)

        var moves = ["", "-wal", "-shm"].map { ext in
            (supportDirectory.appendingPathComponent(databaseName + ext), URL(fileURLWithPath: dbTarget + ext))
        }
        moves.append((supportDirectory.appendingPathComponent(blobsName, isDirectory: true), blobsTarget))

        var done: [(source: URL, target: URL)] = []
        do {
            for (source, target) in moves where fm.fileExists(atPath: source.path) {
                try rename(source, target)
                done.append((source, target))
            }
        } catch {
            for (source, target) in done.reversed() {
                do {
                    try rename(target, source)
                } catch {
                    logFailure("move-aside rollback failed", error)
                }
            }
            throw error
        }
    }

    private static func removeRepairFlag(in supportDirectory: URL) {
        let flag = supportDirectory.appendingPathComponent(repairFlagName)
        guard FileManager.default.fileExists(atPath: flag.path) else { return }
        do {
            try FileManager.default.removeItem(at: flag)
        } catch {
            logFailure("repair flag removal failed", error)
        }
    }

    static func logFailure(_ message: StaticString, _ error: any Error) {
        let e = error as NSError
        Log.store.error("\(message, privacy: .public): \(e.domain, privacy: .public) \(e.code, privacy: .public)")
    }
}
