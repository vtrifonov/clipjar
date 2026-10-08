import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct ClipStoreImageTests {
    private let png = TestImages.png(width: 40, height: 30)

    private func id(of result: IngestResult) -> Int64 {
        switch result {
        case let .inserted(id), let .bumped(id): id
        }
    }

    private func exists(_ fx: StoreFixture, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: fx.blobsURL.appendingPathComponent(name).path)
    }

    @Test(arguments: Backend.allCases)
    func insertWritesBlobAndThumbnail(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let hash = ContentHash.of(imageBytes: png)
        let result = try await fx.store.ingest(image(png), source: nil, at: t0)
        guard case let .inserted(id) = result else {
            Issue.record("expected .inserted, got \(result)")
            return
        }
        #expect(try posixPermissions(fx.blobsURL.appendingPathComponent("\(hash).png")) == 0o600)
        #expect(try posixPermissions(fx.blobsURL.appendingPathComponent("\(hash).thumb.png")) == 0o600)
        let clip = try #require(try fetchClip(fx.writer, id))
        #expect(clip.imagePath == "\(hash).png")
        #expect(clip.thumbnailPath == "\(hash).thumb.png")
        #expect(clip.imageWidth == 40)
        #expect(clip.imageHeight == 30)
        #expect(clip.byteSize == png.count)
    }

    @Test(arguments: Backend.allCases)
    func tiffStoredWithTiffExtension(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let tiff = TestImages.tiff(width: 40, height: 30)
        let result = try await fx.store.ingest(image(tiff, uti: "public.tiff"), source: nil, at: t0)
        let clip = try #require(try fetchClip(fx.writer, id(of: result)))
        #expect(clip.imagePath?.hasSuffix(".tiff") == true)
        #expect(clip.imageType == "public.tiff")
        #expect(exists(fx, try #require(clip.imagePath)))
    }

    @Test(arguments: Backend.allCases)
    func bumpWritesNoNewBlob(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let hash = ContentHash.of(imageBytes: png)
        let blobPath = fx.blobsURL.appendingPathComponent("\(hash).png").path
        let first = try await fx.store.ingest(image(png), source: nil, at: t0)
        let before = try FileManager.default.attributesOfItem(atPath: blobPath)
        let second = try await fx.store.ingest(image(png), source: nil, at: t0 + 60)
        #expect(second == .bumped(id(of: first)))
        let after = try FileManager.default.attributesOfItem(atPath: blobPath)
        #expect(after[.modificationDate] as? Date == before[.modificationDate] as? Date)
        #expect((after[.systemFileNumber] as? NSNumber) == (before[.systemFileNumber] as? NSNumber))
    }

    @Test(arguments: Backend.allCases)
    func bumpRepairsMissingFiles(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let hash = ContentHash.of(imageBytes: png)
        let first = try await fx.store.ingest(image(png), source: nil, at: t0)
        try FileManager.default.removeItem(at: fx.blobsURL.appendingPathComponent("\(hash).png"))
        try FileManager.default.removeItem(at: fx.blobsURL.appendingPathComponent("\(hash).thumb.png"))
        let second = try await fx.store.ingest(image(png), source: nil, at: t0 + 60)
        #expect(second == .bumped(id(of: first)))
        #expect(exists(fx, "\(hash).png"))
        #expect(exists(fx, "\(hash).thumb.png"))
    }

    @Test(arguments: Backend.allCases)
    func thumbnailFailureInsertsWithoutThumbnail(_ backend: Backend) async throws {
        let fx = try makeStore(backend, thumbnailer: { _ in nil })
        let hash = ContentHash.of(imageBytes: png)
        let result = try await fx.store.ingest(image(png), source: nil, at: t0)
        guard case let .inserted(id) = result else {
            Issue.record("expected .inserted, got \(result)")
            return
        }
        #expect(try fetchClip(fx.writer, id)?.thumbnailPath == nil)
        #expect(!exists(fx, "\(hash).thumb.png"))
        #expect(exists(fx, "\(hash).png"))
    }

    @Test(arguments: Backend.allCases)
    func blobWriteFailureInsertsNothing(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fx.blobsURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fx.blobsURL.path) }
        await #expect(throws: (any Error).self) {
            try await fx.store.ingest(image(png), source: nil, at: t0)
        }
        #expect(try clipCount(fx.writer) == 0)
    }

    @Test(arguments: Backend.allCases)
    func transactionFailureRemovesOnlyNewFiles(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let hash = ContentHash.of(imageBytes: png)
        let sentinel = Data("sentinel".utf8)
        let thumbURL = fx.blobsURL.appendingPathComponent("\(hash).thumb.png")
        try sentinel.write(to: thumbURL)
        try await fx.writer.write {
            try $0.execute(sql: "CREATE TRIGGER t_fail BEFORE INSERT ON clip BEGIN SELECT RAISE(ABORT, 'test'); END")
        }
        await #expect(throws: (any Error).self) {
            try await fx.store.ingest(image(png), source: nil, at: t0)
        }
        #expect(!exists(fx, "\(hash).png"))
        #expect(try Data(contentsOf: thumbURL) == sentinel)
    }

    @Test(arguments: Backend.allCases)
    func bumpRepairRollbackRemovesRecreatedBlob(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let hash = ContentHash.of(imageBytes: png)
        try await fx.store.ingest(image(png), source: nil, at: t0)
        try FileManager.default.removeItem(at: fx.blobsURL.appendingPathComponent("\(hash).png"))
        try await fx.writer.write {
            try $0.execute(sql: "CREATE TRIGGER t_fail BEFORE UPDATE ON clip BEGIN SELECT RAISE(ABORT, 'test'); END")
        }
        await #expect(throws: (any Error).self) {
            try await fx.store.ingest(image(png), source: nil, at: t0 + 60)
        }
        #expect(!exists(fx, "\(hash).png"))
        #expect(exists(fx, "\(hash).thumb.png"))
        try await fx.writer.write { try $0.execute(sql: "DROP TRIGGER t_fail") }
        let result = try await fx.store.ingest(image(png), source: nil, at: t0 + 120)
        guard case .bumped = result else {
            Issue.record("expected .bumped, got \(result)")
            return
        }
        #expect(exists(fx, "\(hash).png"))
    }

    @Test func concurrentStoresSameImage() async throws {
        let fx = try makeStore(.filePool)
        let other = try ClipStore(writer: fx.writer, blobsDirectory: fx.blobsURL)
        let hash = ContentHash.of(imageBytes: png)
        async let a = fx.store.ingest(image(png), source: nil, at: t0)
        async let b = other.ingest(image(png), source: nil, at: t0)
        let results = try await [a, b]
        let inserted = results.filter { if case .inserted = $0 { true } else { false } }
        let bumped = results.filter { if case .bumped = $0 { true } else { false } }
        #expect(inserted.count == 1)
        #expect(bumped.count == 1)
        #expect(Set(results.map(id(of:))).count == 1)
        #expect(try clipCount(fx.writer) == 1)
        #expect(exists(fx, "\(hash).png"))
        #expect(exists(fx, "\(hash).thumb.png"))
    }
}
