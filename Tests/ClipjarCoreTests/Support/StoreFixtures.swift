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
