import Foundation
import GRDB
@testable import ClipjarCore

enum Backend: String, CaseIterable, Sendable { case memoryQueue, filePool }

final class TempDir: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipjar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A UserDefaults suite backed by a plist inside a temp directory (an absolute-path suite name), so
/// nothing lands in ~/Library/Preferences; the domain is cleared and the directory removed on release.
final class TempDefaults {
    private let dir: TempDir
    let name: String
    let defaults: UserDefaults

    init() {
        dir = try! TempDir()
        name = dir.url.appendingPathComponent("defaults").path
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

func makeWriter(_ backend: Backend, in dir: TempDir) throws -> any DatabaseWriter {
    switch backend {
    case .memoryQueue:
        return try DatabaseQueue(configuration: Schema.configuration())
    case .filePool:
        return try DatabasePool(
            path: dir.url.appendingPathComponent("clips.sqlite").path,
            configuration: Schema.configuration()
        )
    }
}

func posixPermissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

/// Whole seconds: GRDB stores Dates with millisecond precision.
let t0 = Date(timeIntervalSince1970: 1_800_000_000)

struct StoreFixture {
    let store: ClipStore
    let writer: any DatabaseWriter
    let dir: TempDir
    var blobsURL: URL
}

/// Blobs directory is `dir/blobs`, created 0700.
func makeStore(_ backend: Backend, thumbnailer: (@Sendable (Data) -> Data?)? = nil) throws -> StoreFixture {
    let dir = try TempDir()
    let writer = try makeWriter(backend, in: dir)
    let blobsURL = dir.url.appendingPathComponent("blobs", isDirectory: true)
    try FileManager.default.createDirectory(
        at: blobsURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
    )
    let store = if let thumbnailer {
        try ClipStore(writer: writer, blobsDirectory: blobsURL, thumbnailer: thumbnailer)
    } else {
        try ClipStore(writer: writer, blobsDirectory: blobsURL)
    }
    return StoreFixture(store: store, writer: writer, dir: dir, blobsURL: blobsURL)
}

func text(_ s: String, kind: ClipKind = .text, rtf: Data? = nil, html: Data? = nil) -> CapturedContent {
    CapturedContent(kind: kind, plainText: s, rtf: rtf, html: html)
}

func image(_ data: Data, uti: String = "public.png") -> CapturedContent {
    let size = TestImages.pixelSize(of: data)
    return CapturedContent(
        kind: .image, plainText: "", image: ImageData(data: data, uti: uti),
        width: size?.width, height: size?.height
    )
}

let textEdit = SourceApp(bundleID: "com.apple.TextEdit", name: "TextEdit")
let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")

func fetchClip(_ w: any DatabaseWriter, _ id: Int64) throws -> Clip? {
    try w.read { try Clip.fetchOne($0, key: id) }
}

func clipCount(_ w: any DatabaseWriter) throws -> Int {
    try w.read { try Clip.fetchCount($0) }
}
