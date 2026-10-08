import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct StoreEventTests {
    private func flagURL(_ dir: URL) -> URL {
        dir.appendingPathComponent(StoreOpener.repairFlagName)
    }

    @Test func corruptErrorWritesFlag() throws {
        let dir = try TempDir()
        let event = StoreErrorClassifier.classify(DatabaseError(resultCode: .SQLITE_CORRUPT), supportDirectory: dir.url)
        #expect(event == .corrupt)
        #expect(FileManager.default.fileExists(atPath: flagURL(dir.url).path))
        #expect(try posixPermissions(flagURL(dir.url)) == 0o600)
    }

    @Test func vtabCorruptionIsCorrupt() throws {
        let dir = try TempDir()
        let error = DatabaseError(resultCode: .SQLITE_CORRUPT_VTAB)
        #expect(StoreErrorClassifier.isCorruption(error))
        #expect(StoreErrorClassifier.classify(error, supportDirectory: dir.url) == .corrupt)
    }

    @Test func otherErrorIsWriteFailed() throws {
        let dir = try TempDir()
        let event = StoreErrorClassifier.classify(CocoaError(.fileWriteNoPermission), supportDirectory: dir.url)
        #expect(event == .writeFailed)
        #expect(!FileManager.default.fileExists(atPath: flagURL(dir.url).path))
    }

    @Test func nilSupportDirectory() {
        #expect(StoreErrorClassifier.classify(DatabaseError(resultCode: .SQLITE_CORRUPT), supportDirectory: nil) == .corrupt)
    }

    @Test func flagTriggersRepairOnNextOpen() async throws {
        let dir = try TempDir()
        let support = dir.url.appendingPathComponent("Support", isDirectory: true)
        let first = await StoreOpener.open(supportDirectory: support)
        try first.store.close()
        #expect(StoreErrorClassifier.classify(DatabaseError(resultCode: .SQLITE_CORRUPT), supportDirectory: support) == .corrupt)
        let second = await StoreOpener.open(supportDirectory: support)
        defer { try? second.store.close() }
        #expect(second.ranRepairChecks)
        #expect(!second.recoveredFromCorruption)
    }
}
