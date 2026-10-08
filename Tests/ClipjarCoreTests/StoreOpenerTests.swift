import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct StoreOpenerTests {
    private func supportURL(_ dir: TempDir) -> URL {
        dir.url.appendingPathComponent("Support", isDirectory: true)
    }

    @Test func freshOpenCreatesPrivateLayout() async throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        let r = await StoreOpener.open(supportDirectory: support)
        defer { try? r.store.close() }
        #expect(r.supportDirectory == support)
        #expect(!r.recoveredFromCorruption)
        #expect(!r.storageUnavailable)
        #expect(!r.ranRepairChecks)
        #expect(try posixPermissions(support) == 0o700)
        #expect(try posixPermissions(support.appendingPathComponent("blobs")) == 0o700)
        #expect(try posixPermissions(support.appendingPathComponent("clips.sqlite")) == 0o600)

        let png = TestImages.png(width: 40, height: 30)
        try await r.store.ingest(image(png), source: nil, at: t0)
        for suffix in ["-wal", "-shm"] {
            let url = support.appendingPathComponent("clips.sqlite" + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                #expect(try posixPermissions(url) == 0o600)
            }
        }
        let blob = support.appendingPathComponent("blobs")
            .appendingPathComponent(BlobFiles.imageName(hash: ContentHash.of(imageBytes: png), uti: "public.png"))
        #expect(try posixPermissions(blob) == 0o600)
        let values = try support.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func permissionsReappliedOnOpen() async throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        let first = await StoreOpener.open(supportDirectory: support)
        try first.store.close()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: support.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: support.appendingPathComponent("blobs").path
        )
        let db = support.appendingPathComponent("clips.sqlite")
        let wal = support.appendingPathComponent("clips.sqlite-wal")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: db.path)
        if !FileManager.default.fileExists(atPath: wal.path) {
            FileManager.default.createFile(atPath: wal.path, contents: nil)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: wal.path)
        let second = await StoreOpener.open(supportDirectory: support)
        defer { try? second.store.close() }
        #expect(!second.storageUnavailable)
        #expect(try posixPermissions(support) == 0o700)
        #expect(try posixPermissions(support.appendingPathComponent("blobs")) == 0o700)
        #expect(try posixPermissions(db) == 0o600)
        #expect(try posixPermissions(wal) == 0o600)
    }

    @Test func healthyReopenKeepsData() async throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        let first = await StoreOpener.open(supportDirectory: support)
        let result = try await first.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
        guard case let .inserted(id) = result else {
            Issue.record("expected .inserted, got \(result)")
            return
        }
        try first.store.close()
        let second = await StoreOpener.open(supportDirectory: support)
        defer { try? second.store.close() }
        #expect(!second.recoveredFromCorruption)
        #expect(!second.ranRepairChecks)
        #expect(!second.storageUnavailable)
        #expect(try await second.store.clip(id: id)?.plainText == "Hello, Clipjar")
    }

    @Test func regularFileAtSupportPathFallsBackToMemory() async throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        try Data("synthetic".utf8).write(to: support)
        let r = await StoreOpener.open(supportDirectory: support)
        defer { r.removeTemporaryBlobs() }
        #expect(r.storageUnavailable)
        #expect(r.supportDirectory == nil)
        let result = try await r.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
        guard case .inserted = result else {
            Issue.record("expected .inserted, got \(result)")
            return
        }
    }

    /// Images copied during an in-memory session must not outlive it in `$TMPDIR`.
    @Test func inMemoryTemporaryBlobsRemoved() async throws {
        let r = StoreOpener.openInMemory()
        try await r.store.ingest(image(TestImages.png(width: 40, height: 30)), source: nil, at: t0)
        let blobs = r.store.blobsDirectory
        #expect(try !FileManager.default.contentsOfDirectory(atPath: blobs.path).isEmpty)
        r.removeTemporaryBlobs()
        #expect(!FileManager.default.fileExists(atPath: blobs.path))
        r.removeTemporaryBlobs()
    }

    @Test func persistentBlobsNotRemoved() async throws {
        let dir = try TempDir()
        let r = await StoreOpener.open(supportDirectory: supportURL(dir))
        #expect(!r.storageUnavailable)
        r.removeTemporaryBlobs()
        #expect(FileManager.default.fileExists(atPath: r.store.blobsDirectory.path))
    }

    @Test func openInMemoryWorks() async throws {
        let r = StoreOpener.openInMemory()
        defer { r.removeTemporaryBlobs() }
        #expect(r.storageUnavailable)
        #expect(r.supportDirectory == nil)
        let png = TestImages.png(width: 40, height: 30)
        let result = try await r.store.ingest(image(png), source: nil, at: t0)
        guard case let .inserted(id) = result else {
            Issue.record("expected .inserted, got \(result)")
            return
        }
        #expect(try await r.store.payload(id: id) == .image(ImageData(data: png, uti: "public.png")))
    }
}
