import Foundation
import GRDB

public struct Clip: Identifiable, Sendable, Equatable, Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clip"

    public var id: Int64?
    public var kind: ClipKind
    /// text/link: the text; file: paths joined by "\n"; image: "".
    public var plainText: String
    public var previewText: String
    /// `SearchFolding.fold(plainText)`.
    public var searchText: String
    public var rtfData: Data?
    public var htmlData: Data?
    /// Relative to the blobs directory, "<hash>.png".
    public var imagePath: String?
    /// "public.png" | "public.tiff".
    public var imageType: String?
    /// "<hash>.thumb.png".
    public var thumbnailPath: String?
    /// Absolute file:// URL strings (GRDB stores them as JSON text).
    public var fileURLs: [String]
    /// Lowercase hex SHA-256.
    public var contentHash: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var createdAt: Date
    public var lastCopiedAt: Date
    public var isPinned: Bool
    public var byteSize: Int
    public var imageWidth: Int?
    public var imageHeight: Int?

    public init(
        id: Int64? = nil,
        kind: ClipKind,
        plainText: String,
        previewText: String,
        searchText: String,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        imagePath: String? = nil,
        imageType: String? = nil,
        thumbnailPath: String? = nil,
        fileURLs: [String] = [],
        contentHash: String,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        createdAt: Date,
        lastCopiedAt: Date,
        isPinned: Bool = false,
        byteSize: Int,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.plainText = plainText
        self.previewText = previewText
        self.searchText = searchText
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imagePath = imagePath
        self.imageType = imageType
        self.thumbnailPath = thumbnailPath
        self.fileURLs = fileURLs
        self.contentHash = contentHash
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.isPinned = isPinned
        self.byteSize = byteSize
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
