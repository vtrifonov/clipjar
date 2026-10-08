import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct ClipStoreScrubTests {
    private let secret = "SYNTHETIC-SECRET-7f3a9c"

    private func id(of result: IngestResult) -> Int64 {
        switch result {
        case let .inserted(id), let .bumped(id): id
        }
    }

    /// Searches the UTF-8 bytes of every `clips.sqlite*` file in `dir`.
    private func dbBytesContain(_ needle: String, in dir: URL) throws -> Bool {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("clips.sqlite") }
        let bytes = Data(needle.utf8)
        return try names.contains { name in
            try Data(contentsOf: dir.appendingPathComponent(name)).range(of: bytes) != nil
        }
    }

    /// Unpinned rows older than any ingest made at `t0` or later.
    private func olderItems(_ count: Int) -> [Clip] {
        (0..<count).map { Clip.make("Item \($0)", at: t0 - 1000 + Double($0)) }
    }

    private func ingestSecretAndOthers(_ fx: StoreFixture) async throws -> Int64 {
        let secretID = id(of: try await fx.store.ingest(text(secret), source: nil, at: t0))
        for i in 1...5 {
            try await fx.store.ingest(text("Other item \(i)"), source: nil, at: t0 + Double(i))
        }
        #expect(try dbBytesContain(secret, in: fx.dir.url))
        return secretID
    }

    @Test func userDeleteScrubsBytesImmediately() async throws {
        let fx = try makeStore(.filePool)
        let secretID = try await ingestSecretAndOthers(fx)
        try await fx.store.delete(id: secretID)
        #expect(try !dbBytesContain(secret, in: fx.dir.url))
    }

    @Test func conditionalDeleteScrubs() async throws {
        let fx = try makeStore(.filePool)
        let secretID = try await ingestSecretAndOthers(fx)
        #expect(try await fx.store.delete(id: secretID, ifLastCopiedAt: t0) == true)
        #expect(try !dbBytesContain(secret, in: fx.dir.url))
    }

    @Test func clearAllScrubsBytes() async throws {
        let fx = try makeStore(.filePool)
        try await fx.store.ingest(text(secret), source: nil, at: t0)
        let pinned = id(of: try await fx.store.ingest(text("Pinned other"), source: nil, at: t0 + 1))
        try await fx.store.setPinned(id: pinned, true)
        #expect(try dbBytesContain(secret, in: fx.dir.url))
        #expect(try await fx.store.clearAll(keepPinned: true) == 1)
        #expect(try !dbBytesContain(secret, in: fx.dir.url))
    }

    @Test(arguments: Backend.allCases)
    func pruneDefersOptimize(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        await fx.store.configure(limit: .l200, maxAgeDays: 0)
        try seed(fx.writer, olderItems(200))
        for i in 0..<50 {
            try await fx.store.ingest(text("New item \(i)"), source: nil, at: t0 + Double(i))
        }
        #expect(try clipCount(fx.writer) == 200)
        #expect(await fx.store.optimizeRunCount <= 1)
    }

    @Test func scrubIfPendingRemovesPrunedText() async throws {
        let fx = try makeStore(.filePool)
        await fx.store.configure(limit: .l200, maxAgeDays: 0)
        try seed(fx.writer, olderItems(200))
        try await fx.store.ingest(text("First new item"), source: nil, at: t0)
        #expect(await fx.store.optimizeRunCount == 1)
        try seed(fx.writer, [Clip.make(secret, at: t0 - 5000)])
        #expect(try dbBytesContain(secret, in: fx.dir.url))
        try await fx.store.ingest(text("Second new item"), source: nil, at: t0 + 60)
        #expect(try await fx.writer.read { try ClipQuery(terms: ["secret"]).fetchCount($0) } == 0)
        #expect(await fx.store.scrubPending == true)
        #expect(await fx.store.optimizeRunCount == 1)
        #expect(try dbBytesContain(secret, in: fx.dir.url))
        try await fx.store.scrubIfPending()
        #expect(try !dbBytesContain(secret, in: fx.dir.url))
        #expect(await fx.store.optimizeRunCount == 2)
        #expect(await fx.store.scrubPending == false)
    }

    @Test(arguments: Backend.allCases)
    func scrubIfPendingNoopWhenClean(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        try await fx.store.scrubIfPending()
        #expect(await fx.store.optimizeRunCount == 0)
    }

    @Test(arguments: Backend.allCases)
    func userDeleteScrubFailureDoesNotThrow(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let clipID = id(of: try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0))
        await fx.store.setScrubFaultForTesting(CocoaError(.fileWriteUnknown))
        try await fx.store.delete(id: clipID)
        #expect(try await fx.store.clip(id: clipID) == nil)
        #expect(await fx.store.scrubPending == true)
        #expect(await fx.store.optimizeRunCount == 0)
        await fx.store.setScrubFaultForTesting(nil)
        try await fx.store.scrubIfPending()
        #expect(await fx.store.scrubPending == false)
        #expect(await fx.store.optimizeRunCount == 1)
    }

    @Test(arguments: Backend.allCases)
    func userDeleteScrubCorruptionIsThrown(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let clipID = id(of: try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0))
        await fx.store.setScrubFaultForTesting(DatabaseError(resultCode: .SQLITE_CORRUPT_VTAB))
        await #expect {
            try await fx.store.delete(id: clipID)
        } throws: { error in
            StoreErrorClassifier.classify(error, supportDirectory: fx.dir.url) == .corrupt
        }
        #expect(FileManager.default.fileExists(atPath: fx.dir.url.appendingPathComponent(StoreOpener.repairFlagName).path))
        #expect(try await fx.store.clip(id: clipID) == nil)
        #expect(await fx.store.scrubPending == true)
    }

    @Test(arguments: Backend.allCases)
    func pruneScrubCorruptionReachesIngestCaller(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        await fx.store.configure(limit: .l200, maxAgeDays: 0)
        try seed(fx.writer, olderItems(200))
        await fx.store.setScrubFaultForTesting(DatabaseError(resultCode: .SQLITE_CORRUPT))
        await #expect {
            try await fx.store.ingest(text("New item"), source: nil, at: t0)
        } throws: { StoreErrorClassifier.isCorruption($0) }
        #expect(try await fx.writer.read { try ClipQuery(terms: ["new item"]).fetchCount($0) } == 1)
        #expect(try clipCount(fx.writer) == 200)
    }

    @Test(arguments: Backend.allCases)
    func failedClearAllScrubRetriesWithRebuild(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        await fx.store.configure(limit: .l200, maxAgeDays: 0)
        try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
        await fx.store.setScrubFaultForTesting(CocoaError(.fileWriteUnknown))
        #expect(try await fx.store.clearAll(keepPinned: true) == 1)
        #expect(await fx.store.pendingScrub == .rebuild)
        // A later prune-driven pending scrub never downgrades the pending rebuild.
        try seed(fx.writer, olderItems(201))
        try await fx.store.ingest(text("New item"), source: nil, at: t0 + 1)
        #expect(await fx.store.pendingScrub == .rebuild)
        await fx.store.setScrubFaultForTesting(nil)
        try await fx.store.scrubIfPending()
        #expect(await fx.store.lastScrubCommand == .rebuild)
        #expect(await fx.store.pendingScrub == nil)
    }

    @Test(arguments: Backend.allCases)
    func hourlyScrubRuns(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        await fx.store.configure(limit: .l200, maxAgeDays: 0)
        try seed(fx.writer, olderItems(200))
        try await fx.store.ingest(text("First new item"), source: nil, at: t0)
        try await fx.store.ingest(text("Second new item"), source: nil, at: t0 + 60)
        #expect(await fx.store.scrubPending == true)
        #expect(await fx.store.optimizeRunCount == 1)
        try await fx.store.ingest(text("Third new item"), source: nil, at: t0 + 3700)
        #expect(await fx.store.optimizeRunCount == 2)
        #expect(await fx.store.scrubPending == false)
    }
}
