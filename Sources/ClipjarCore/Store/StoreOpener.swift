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

    /// Any failure falls back to `openInMemory()`.
    public static func open(supportDirectory: URL, now: Date = Date()) async -> OpenResult {
        do {
            try prepareLayout(supportDirectory)
            let store = try openStore(supportDirectory)
            return OpenResult(
                store: store, recoveredFromCorruption: false, storageUnavailable: false,
                ranRepairChecks: false, supportDirectory: supportDirectory
            )
        } catch {
            logFailure("store open failed", error)
            return openInMemory()
        }
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

    /// Support dir and `blobs/` are 0700 and the support dir is excluded from backup, re-applied on every
    /// launch; a missing database file is created empty with 0600 before the pool opens it.
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
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = supportDirectory
        try url.setResourceValues(values)
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

    static func logFailure(_ message: StaticString, _ error: any Error) {
        let e = error as NSError
        Log.store.error("\(message, privacy: .public): \(e.domain, privacy: .public) \(e.code, privacy: .public)")
    }
}
