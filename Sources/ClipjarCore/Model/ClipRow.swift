import Foundation
import GRDB

public struct ClipRow: Identifiable, Sendable, Equatable, FetchableRecord, Decodable {
    public var id: Int64
    public var kind: ClipKind
    public var previewText: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var lastCopiedAt: Date
    public var isPinned: Bool
    public var thumbnailPath: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var byteSize: Int
    /// `json_array_length(fileURLs)`; needed for the "3 files" row text.
    public var fileCount: Int
}
