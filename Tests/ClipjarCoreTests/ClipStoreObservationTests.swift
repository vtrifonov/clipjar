import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct ClipStoreObservationTests {
    private func id(of result: IngestResult) -> Int64 {
        switch result {
        case let .inserted(id), let .bumped(id): id
        }
    }

    @Test(arguments: Backend.allCases)
    func rowsObservationEmitsOnIngest(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        var it = fx.store.rowsObservation(.all).values(in: fx.store.reader).makeAsyncIterator()
        #expect(try await it.next() == [])
        let clipID = id(of: try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0))
        let rows = try #require(try await it.next())
        #expect(rows.map { $0.id } == [clipID])
    }

    @Test(arguments: Backend.allCases)
    func countObservationTracksQuery(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let obs = fx.store.countObservation(ClipQuery(kinds: [.link]))
        var it = obs.values(in: fx.store.reader).makeAsyncIterator()
        #expect(try await it.next() == 0)
        try await fx.store.ingest(text("https://example.com/docs", kind: .link), source: nil, at: t0)
        #expect(try await it.next() == 1)
    }

    @Test(arguments: Backend.allCases)
    func clipObservationTracksPin(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let clipID = id(of: try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0))
        var it = fx.store.clipObservation(id: clipID).values(in: fx.store.reader).makeAsyncIterator()
        let first = try await it.next()
        #expect(first??.isPinned == false)
        try await fx.store.setPinned(id: clipID, true)
        let next = try await it.next()
        #expect(next??.isPinned == true)
    }

    @Test(arguments: Backend.allCases)
    func pagedQueryReturnsNewest(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let seeded = try seed(fx.writer, (0..<250).map { Clip.make("Item \($0)", at: t0 + Double($0)) })
        var it = fx.store.rowsObservation(ClipQuery(limit: 100)).values(in: fx.store.reader).makeAsyncIterator()
        let rows = try #require(try await it.next())
        #expect(rows.count == 100)
        #expect(rows.first?.id == seeded.last)
    }

    @Test(arguments: Backend.allCases)
    func orphanCleanupHonoursGraceAndReferences(_ backend: Backend) async throws {
        let fx = try makeStore(backend, thumbnailer: { _ in nil })
        let png = TestImages.png(width: 40, height: 30)
        let clipID = id(of: try await fx.store.ingest(image(png), source: nil, at: t0))
        let referenced = try #require(try fetchClip(fx.writer, clipID)?.imagePath)
        let now = Date()
        let hourAgo = now.addingTimeInterval(-3600)
        func place(_ name: String, modified: Date) throws {
            let url = fx.blobsURL.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { try Data("synthetic".utf8).write(to: url) }
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        try place(referenced, modified: hourAgo)
        try place("old.png", modified: hourAgo)
        try place("fresh.png", modified: now)
        try place("x.tmp", modified: hourAgo)
        #expect(try await fx.store.cleanOrphanBlobs(now: now) == 2)
        let remaining = try Set(FileManager.default.contentsOfDirectory(atPath: fx.blobsURL.path))
        #expect(remaining == [referenced, "fresh.png"])
    }
}
