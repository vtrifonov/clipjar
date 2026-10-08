import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct ClipStoreMutationTests {
    private let png = TestImages.png(width: 40, height: 30)

    private func id(of result: IngestResult) -> Int64 {
        switch result {
        case let .inserted(id), let .bumped(id): id
        }
    }

    private func exists(_ fx: StoreFixture, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: fx.blobsURL.appendingPathComponent(name).path)
    }

    private func search(_ fx: StoreFixture, _ term: String) async throws -> [ClipRow] {
        try await fx.writer.read { try ClipQuery(terms: [term]).fetchRows($0) }
    }

    @Test(arguments: Backend.allCases)
    func touchMovesToTop(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let older = id(of: try await fx.store.ingest(text("Older"), source: nil, at: t0))
        try await fx.store.ingest(text("Newer"), source: nil, at: t0 + 1)
        try await fx.store.touch(id: older, at: t0 + 100)
        let rows = try await fx.writer.read { try ClipQuery.all.fetchRows($0) }
        #expect(rows.first?.id == older)
    }

    @Test(arguments: Backend.allCases)
    func setPinnedRoundTrip(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let clipID = id(of: try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0))
        try await fx.store.setPinned(id: clipID, true)
        #expect(try await fx.store.clip(id: clipID)?.isPinned == true)
        try await fx.store.setPinned(id: clipID, false)
        #expect(try await fx.store.clip(id: clipID)?.isPinned == false)
    }

    @Test(arguments: Backend.allCases)
    func deleteRemovesRowAndBlobs(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let hash = ContentHash.of(imageBytes: png)
        let clipID = id(of: try await fx.store.ingest(image(png), source: nil, at: t0))
        try await fx.store.delete(id: clipID)
        #expect(try await fx.store.clip(id: clipID) == nil)
        #expect(!exists(fx, "\(hash).png"))
        #expect(!exists(fx, "\(hash).thumb.png"))
    }

    @Test(arguments: Backend.allCases)
    func deletedClipNoLongerMatchesSearch(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let clipID = id(of: try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0))
        #expect(try await search(fx, "clipjar").count == 1)
        try await fx.store.delete(id: clipID)
        #expect(try await search(fx, "clipjar") == [])
    }

    @Test(arguments: Backend.allCases)
    func deleteUnknownIdIsNoop(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
        try await fx.store.delete(id: 9_999)
        #expect(try clipCount(fx.writer) == 1)
    }

    @Test(arguments: Backend.allCases)
    func conditionalDeleteMatches(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let clipID = id(of: try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0))
        #expect(try await fx.store.delete(id: clipID, ifLastCopiedAt: t0) == true)
        #expect(try await fx.store.clip(id: clipID) == nil)
    }

    @Test(arguments: Backend.allCases)
    func conditionalDeleteAfterBumpDeletesNothing(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let clipID = id(of: try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0))
        try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0 + 5)
        #expect(try await fx.store.delete(id: clipID, ifLastCopiedAt: t0) == false)
        #expect(try await fx.store.clip(id: clipID) != nil)
    }

    @Test(arguments: Backend.allCases)
    func clearAllKeepsPinned(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let hash = ContentHash.of(imageBytes: png)
        try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
        try await fx.store.ingest(text("Second item"), source: nil, at: t0 + 1)
        try await fx.store.ingest(image(png), source: nil, at: t0 + 2)
        let pinnedA = id(of: try await fx.store.ingest(text("Pinned one"), source: nil, at: t0 + 3))
        let pinnedB = id(of: try await fx.store.ingest(text("Pinned two"), source: nil, at: t0 + 4))
        try await fx.store.setPinned(id: pinnedA, true)
        try await fx.store.setPinned(id: pinnedB, true)
        #expect(try await fx.store.clearAll(keepPinned: true) == 3)
        let remaining = try await fx.writer.read { try ClipQuery.all.fetchRows($0) }
        #expect(Set(remaining.map(\.id)) == [pinnedA, pinnedB])
        #expect(remaining.allSatisfy { $0.isPinned })
        #expect(!exists(fx, "\(hash).png"))
        #expect(!exists(fx, "\(hash).thumb.png"))
        #expect(try await search(fx, "clipjar") == [])
    }

    @Test(arguments: Backend.allCases)
    func clearAllIncludingPinned(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
        let pinned = id(of: try await fx.store.ingest(text("Pinned one"), source: nil, at: t0 + 1))
        try await fx.store.setPinned(id: pinned, true)
        #expect(try await fx.store.clearAll(keepPinned: false) == 2)
        #expect(try clipCount(fx.writer) == 0)
    }

    @Test(arguments: Backend.allCases)
    func payloadText(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let rtf = Data("{\\rtf1 Hello, Clipjar}".utf8)
        let clipID = id(of: try await fx.store.ingest(text("Hello, Clipjar", rtf: rtf), source: nil, at: t0))
        #expect(try await fx.store.payload(id: clipID) == .text(plain: "Hello, Clipjar", rtf: rtf, html: nil))
    }

    @Test(arguments: Backend.allCases)
    func payloadImage(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let clipID = id(of: try await fx.store.ingest(image(png), source: nil, at: t0))
        #expect(try await fx.store.payload(id: clipID) == .image(ImageData(data: png, uti: "public.png")))
    }

    @Test(arguments: Backend.allCases)
    func payloadImageMissingBlobIsNil(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let hash = ContentHash.of(imageBytes: png)
        let clipID = id(of: try await fx.store.ingest(image(png), source: nil, at: t0))
        try FileManager.default.removeItem(at: fx.blobsURL.appendingPathComponent("\(hash).png"))
        #expect(try await fx.store.payload(id: clipID) == nil)
    }

    @Test(arguments: Backend.allCases)
    func payloadFilesRoundTripUnicode(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let url = URL(fileURLWithPath: fx.dir.url.path + "/résumé draft.txt")
        let capture = CapturedContent(kind: .file, plainText: "", fileURLs: [url])
        let clipID = id(of: try await fx.store.ingest(capture, source: nil, at: t0))
        #expect(try await fx.store.payload(id: clipID) == .files([url]))
    }

    @Test(arguments: Backend.allCases)
    func payloadUnknownIdIsNil(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        #expect(try await fx.store.payload(id: 9_999) == nil)
    }
}
