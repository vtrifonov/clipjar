import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@MainActor @Suite struct StoreErrorReporterTests {
    @MainActor final class EventLog {
        var events: [StoreEvent] = []
    }

    private func flagExists(_ dir: TempDir) -> Bool {
        FileManager.default.fileExists(atPath: dir.url.appendingPathComponent(StoreOpener.repairFlagName).path)
    }

    @Test func corruptionFlagsRepairAndReportsCorrupt() async throws {
        let dir = try TempDir()
        let log = EventLog()
        let reporter = StoreErrorReporter(supportDirectory: dir.url) { log.events.append($0) }
        let value: Int? = await reporter.reportIfStoreError { throw DatabaseError(resultCode: .SQLITE_CORRUPT_VTAB) }
        #expect(value == nil)
        #expect(log.events == [.corrupt])
        #expect(flagExists(dir))
    }

    @Test func otherErrorReportsWriteFailed() async throws {
        let dir = try TempDir()
        let log = EventLog()
        let reporter = StoreErrorReporter(supportDirectory: dir.url) { log.events.append($0) }
        reporter.report(DatabaseError(resultCode: .SQLITE_FULL))
        #expect(log.events == [.writeFailed])
        #expect(!flagExists(dir))
    }

    @Test func successReturnsValueAndReportsNothing() async throws {
        let log = EventLog()
        let reporter = StoreErrorReporter(supportDirectory: nil) { log.events.append($0) }
        let value = await reporter.reportIfStoreError { 42 }
        #expect(value == 42)
        #expect(log.events.isEmpty)
    }
}
