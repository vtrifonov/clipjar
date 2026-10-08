import Foundation
import GRDB
import Testing
@testable import ClipjarCore

extension Clip {
    static func make(
        _ text: String,
        kind: ClipKind = .text,
        at date: Date = t0,
        pinned: Bool = false,
        app: String? = "TextEdit",
        bundleID: String? = "com.apple.TextEdit"
    ) -> Clip {
        Clip(
            kind: kind,
            plainText: text,
            previewText: text,
            searchText: SearchFolding.fold(text),
            contentHash: ContentHash.of(kind: kind, plainText: text),
            sourceBundleID: bundleID,
            sourceAppName: app,
            createdAt: date,
            lastCopiedAt: date,
            isPinned: pinned,
            byteSize: text.utf8.count
        )
    }
}

@discardableResult
func seed(_ w: any DatabaseWriter, _ clips: [Clip]) throws -> [Int64] {
    try w.write { db in
        try clips.map { clip in
            var c = clip
            try c.insert(db)
            return try #require(c.id)
        }
    }
}
