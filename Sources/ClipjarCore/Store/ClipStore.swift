import Foundation
import GRDB

public actor ClipStore {
    nonisolated let writer: any DatabaseWriter
    public nonisolated let reader: any DatabaseReader
    public nonisolated let blobsDirectory: URL
    let blobs: BlobFiles
    let thumbnailer: @Sendable (Data) -> Data?
    var limit: HistoryLimit = .l1000
    var maxAgeDays = 0
    private(set) var optimizeRunCount = 0
    /// Set when deleted rows' bytes have not been scrubbed yet.
    private(set) var scrubPending = false
    /// Set only by prune-driven scrubs; user deletions take no `now`.
    private var lastScrubAt: Date?
    /// Test seam: when set, every scrub throws this before touching the database.
    private var scrubFault: (any Error)?

    func setScrubFaultForTesting(_ error: (any Error)?) {
        scrubFault = error
    }

    /// Runs `Schema.migrator`.
    public init(writer: any DatabaseWriter, blobsDirectory: URL) throws {
        try self.init(writer: writer, blobsDirectory: blobsDirectory, thumbnailer: { BlobFiles.thumbnail(for: $0) })
    }

    /// Test seam for the thumbnailer.
    init(writer: any DatabaseWriter, blobsDirectory: URL, thumbnailer: @escaping @Sendable (Data) -> Data?) throws {
        try Schema.migrator.migrate(writer)
        self.writer = writer
        self.reader = writer
        self.blobsDirectory = blobsDirectory
        self.blobs = BlobFiles(directory: blobsDirectory)
        self.thumbnailer = thumbnailer
    }

    /// Image files are written before the transaction; lookup by hash and bump-or-insert run in one
    /// write transaction. If that transaction fails, only the files this call created are removed.
    /// A prune failure after the commit is logged and never fails the ingest.
    @discardableResult
    public func ingest(_ c: CapturedContent, source: SourceApp?, at now: Date) throws -> IngestResult {
        let hash = ContentHash.of(c)
        let files = c.kind == .image ? try c.image.map { try writeImageFiles($0, hash: hash) } : nil
        let result: IngestResult
        do {
            result = try writer.write { db in
                if var existing = try Clip.filter(Column("contentHash") == hash).fetchOne(db) {
                    try Self.bump(&existing, with: c, files: files, source: source, now: now, db: db)
                    return .bumped(try Self.requireID(existing))
                }
                var clip = ClipBuilder.makeClip(from: c, hash: hash, source: source, now: now)
                if let files {
                    clip.imagePath = files.imagePath
                    clip.thumbnailPath = files.newThumbnailPath
                }
                try clip.insert(db)
                return .inserted(try Self.requireID(clip))
            }
        } catch {
            blobs.remove(files?.created ?? [])
            throw error
        }
        do {
            try prune(limit: limit, maxAgeDays: maxAgeDays, now: now)
        } catch {
            let e = error as NSError
            Log.store.error("prune after ingest failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
        }
        return result
    }

    public nonisolated func close() throws {
        try writer.close()
    }

    private struct ImageFiles {
        var imagePath: String
        /// Set when this call produced a thumbnail.
        var newThumbnailPath: String?
        /// Set when the thumbnail file exists on disk, whoever wrote it.
        var existingThumbnailPath: String?
        var created: [String]
    }

    /// A write failure removes anything this call created and rethrows.
    private func writeImageFiles(_ image: ImageData, hash: String) throws -> ImageFiles {
        let name = BlobFiles.imageName(hash: hash, uti: image.uti)
        let thumbName = BlobFiles.thumbnailName(hash: hash)
        let thumb = thumbnailer(image.data)
        var created: [String] = []
        do {
            if try blobs.writeIfAbsent(image.data, name: name) { created.append(name) }
            if let thumb, try blobs.writeIfAbsent(thumb, name: thumbName) { created.append(thumbName) }
        } catch {
            blobs.remove(created)
            throw error
        }
        return ImageFiles(
            imagePath: name,
            newThumbnailPath: thumb != nil ? thumbName : nil,
            existingThumbnailPath: thumb != nil || blobs.exists(thumbName) ? thumbName : nil,
            created: created
        )
    }

    /// `updateChanges` writes only changed columns, so the `searchText` FTS trigger never fires.
    private static func bump(
        _ existing: inout Clip, with c: CapturedContent, files: ImageFiles?, source: SourceApp?, now: Date,
        db: Database
    ) throws {
        try existing.updateChanges(db) { clip in
            clip.lastCopiedAt = now
            if let source {
                clip.sourceBundleID = source.bundleID
                clip.sourceAppName = source.name
            }
            if clip.rtfData == nil, let rtf = c.rtf { clip.rtfData = rtf }
            if clip.htmlData == nil, let html = c.html { clip.htmlData = html }
            if let files {
                if clip.imagePath == nil { clip.imagePath = files.imagePath }
                if clip.thumbnailPath == nil { clip.thumbnailPath = files.existingThumbnailPath }
            }
        }
    }

    private static func requireID(_ clip: Clip) throws -> Int64 {
        guard let id = clip.id else { throw DatabaseError(resultCode: .SQLITE_INTERNAL, message: "missing row id") }
        return id
    }
}

extension ClipStore {
    public func configure(limit: HistoryLimit, maxAgeDays: Int) {
        self.limit = limit
        self.maxAgeDays = maxAgeDays
    }

    /// Deletes unpinned rows older than `maxAgeDays` or beyond `limit`, then removes their blob files.
    /// The full scrub is deferred to at most once per hour; `scrubIfPending` completes it.
    @discardableResult
    public func prune(limit: HistoryLimit, maxAgeDays: Int, now: Date) throws -> Int {
        guard let candidates = Self.pruneCandidates(limit: limit, maxAgeDays: maxAgeDays, now: now) else { return 0 }
        let deleted = try writer.write { db in
            let deleted = try Self.deleteRows(db, where: "id IN (\(literal: candidates))")
            if deleted.count > 0 {
                try db.execute(sql: "INSERT INTO clip_fts(clip_fts, rank) VALUES('merge', 16)")
            }
            return deleted
        }
        blobs.remove(deleted.blobNames)
        guard deleted.count > 0 else { return 0 }
        scrubPending = true
        if lastScrubAt.map({ now.timeIntervalSince($0) >= 3600 }) ?? true {
            scrubAfterCommittedDelete(.optimize, at: now)
        }
        return deleted.count
    }

    /// The deletion already committed, so a scrub failure is logged and left pending rather than thrown.
    private func scrubAfterCommittedDelete(_ command: FTSScrub, at now: Date?) {
        do {
            try scrub(command, at: now)
        } catch {
            scrubPending = true
            let e = error as NSError
            Log.store.error("scrub failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
        }
    }

    /// Completes a deferred prune scrub; called on app termination.
    public func scrubIfPending() throws {
        if scrubPending { try scrub(.optimize, at: nil) }
    }

    enum FTSScrub: String { case optimize, rebuild }

    /// Rewrites the FTS index without deleted entries, then truncates the WAL so that, with
    /// `secure_delete`, no deleted bytes remain in `clips.sqlite*`.
    private func scrub(_ command: FTSScrub, at now: Date?) throws {
        if let scrubFault { throw scrubFault }
        try writer.write { db in
            try db.execute(sql: "INSERT INTO clip_fts(clip_fts) VALUES(?)", arguments: [command.rawValue])
        }
        try writer.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
        optimizeRunCount += 1
        scrubPending = false
        if let now { lastScrubAt = now }
    }

    /// Read-only: how many rows `prune` would delete.
    public func pruneCount(limit: HistoryLimit, maxAgeDays: Int, now: Date) throws -> Int {
        guard let candidates = Self.pruneCandidates(limit: limit, maxAgeDays: maxAgeDays, now: now) else { return 0 }
        return try reader.read { db in
            try SQLRequest<Int>(literal: "SELECT COUNT(*) FROM (\(literal: candidates))").fetchOne(db) ?? 0
        }
    }

    /// Ids of unpinned rows past the age cutoff, unioned with unpinned rows beyond the limit.
    /// Pins never count toward the limit. nil when neither rule is active.
    static func pruneCandidates(limit: HistoryLimit, maxAgeDays: Int, now: Date) -> SQL? {
        var parts: [SQL] = []
        if maxAgeDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
            parts.append("SELECT id FROM clip WHERE isPinned = 0 AND lastCopiedAt < \(cutoff)")
        }
        if limit != .unlimited {
            parts.append("""
                SELECT id FROM (SELECT id FROM clip WHERE isPinned = 0
                ORDER BY lastCopiedAt DESC, id DESC LIMIT -1 OFFSET \(limit.rawValue))
                """)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " UNION ")
    }

    /// Collects the blob names of the matching rows, then deletes them. Call inside a write transaction;
    /// remove the returned blob names only after it commits.
    static func deleteRows(_ db: Database, where condition: SQL) throws -> (count: Int, blobNames: [String]) {
        let rows = try SQLRequest<Row>(literal: "SELECT imagePath, thumbnailPath FROM clip WHERE \(condition)")
            .fetchAll(db)
        let names = rows.flatMap { row -> [String] in
            [row["imagePath"] as String?, row["thumbnailPath"] as String?].compactMap { $0 }
        }
        try db.execute(literal: "DELETE FROM clip WHERE \(condition)")
        return (db.changesCount, names)
    }
}

extension ClipStore {
    public func touch(id: Int64, at now: Date) throws {
        try writer.write { db in
            try db.execute(literal: "UPDATE clip SET lastCopiedAt = \(now) WHERE id = \(id)")
        }
    }

    public func setPinned(id: Int64, _ pinned: Bool) throws {
        try writer.write { db in
            try db.execute(literal: "UPDATE clip SET isPinned = \(pinned) WHERE id = \(id)")
        }
    }

    public func delete(id: Int64) throws {
        try deleteCommitted(where: "id = \(id)", scrub: .optimize)
    }

    /// Deletes only if the clip was not re-copied since `ifLastCopiedAt`; true iff a row was deleted.
    @discardableResult
    public func delete(id: Int64, ifLastCopiedAt: Date) throws -> Bool {
        try deleteCommitted(where: "id = \(id) AND lastCopiedAt = \(ifLastCopiedAt)", scrub: .optimize) > 0
    }

    /// Deletes every unpinned clip, or every clip when `keepPinned` is false.
    @discardableResult
    public func clearAll(keepPinned: Bool) throws -> Int {
        try deleteCommitted(where: keepPinned ? "isPinned = 0" : "1", scrub: .rebuild)
    }

    /// nil for an unknown id, or for an image whose blob file is missing.
    public func payload(id: Int64) throws -> ClipPayload? {
        guard let clip = try clip(id: id) else { return nil }
        switch clip.kind {
        case .text, .link:
            return .text(plain: clip.plainText, rtf: clip.rtfData, html: clip.htmlData)
        case .image:
            guard let path = clip.imagePath, let uti = clip.imageType, let data = blobs.read(path) else { return nil }
            return .image(ImageData(data: data, uti: uti))
        case .file:
            return .files(clip.fileURLs.compactMap(URL.init(string:)))
        }
    }

    public func clip(id: Int64) throws -> Clip? {
        try reader.read { try Clip.fetchOne($0, key: id) }
    }

    /// User deletion: deletes rows in one transaction, removes their blob files after it commits,
    /// then scrubs immediately if anything was deleted.
    @discardableResult
    private func deleteCommitted(where condition: SQL, scrub command: FTSScrub) throws -> Int {
        let deleted = try writer.write { db in try Self.deleteRows(db, where: condition) }
        blobs.remove(deleted.blobNames)
        if deleted.count > 0 { scrubAfterCommittedDelete(command, at: nil) }
        return deleted.count
    }
}
