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

    /// Lookup by hash and bump-or-insert run in one write transaction.
    @discardableResult
    public func ingest(_ c: CapturedContent, source: SourceApp?, at now: Date) throws -> IngestResult {
        let hash = ContentHash.of(c)
        return try writer.write { db in
            if var existing = try Clip.filter(Column("contentHash") == hash).fetchOne(db) {
                try Self.bump(&existing, with: c, source: source, now: now, db: db)
                return .bumped(try Self.requireID(existing))
            }
            var clip = ClipBuilder.makeClip(from: c, hash: hash, source: source, now: now)
            try clip.insert(db)
            return .inserted(try Self.requireID(clip))
        }
    }

    public nonisolated func close() throws {
        try writer.close()
    }

    /// `updateChanges` writes only changed columns, so the `searchText` FTS trigger never fires.
    private static func bump(
        _ existing: inout Clip, with c: CapturedContent, source: SourceApp?, now: Date, db: Database
    ) throws {
        try existing.updateChanges(db) { clip in
            clip.lastCopiedAt = now
            if let source {
                clip.sourceBundleID = source.bundleID
                clip.sourceAppName = source.name
            }
            if clip.rtfData == nil, let rtf = c.rtf { clip.rtfData = rtf }
            if clip.htmlData == nil, let html = c.html { clip.htmlData = html }
        }
    }

    private static func requireID(_ clip: Clip) throws -> Int64 {
        guard let id = clip.id else { throw DatabaseError(resultCode: .SQLITE_INTERNAL, message: "missing row id") }
        return id
    }
}
