import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct CaptureQueueTests {
    @MainActor final class EventLog {
        var events: [StoreEvent] = []
        nonisolated init() {}
    }

    private func previews(_ w: any DatabaseWriter) throws -> [String] {
        try w.read { try ClipQuery.all.fetchRows($0) }.map(\.previewText)
    }

    @Test(arguments: Backend.allCases)
    func itemsBufferedBeforeStartAreIngestedInOrder(_ backend: Backend) async throws {
        let f = try makeStore(backend)
        let queue = CaptureQueue()
        queue.yield(CaptureItem(content: text("one"), source: textEdit, at: t0))
        queue.yield(CaptureItem(content: text("two"), source: textEdit, at: t0.addingTimeInterval(1)))
        queue.yield(CaptureItem(content: text("three"), source: safari, at: t0.addingTimeInterval(2)))
        let task = queue.startConsuming(store: f.store, supportDirectory: nil) { _ in }
        queue.finish()
        await task.value
        #expect(try previews(f.writer) == ["three", "two", "one"])
    }

    @Test(arguments: Backend.allCases)
    func ingestErrorEmitsWriteFailedAndContinues(_ backend: Backend) async throws {
        let f = try makeStore(backend)
        try await f.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_bad BEFORE INSERT ON clip WHEN new.plainText = 'bad'
                BEGIN SELECT RAISE(ABORT, 'x'); END
                """)
        }
        let log = EventLog()
        let queue = CaptureQueue()
        let task = queue.startConsuming(store: f.store, supportDirectory: f.dir.url) { log.events.append($0) }
        queue.yield(CaptureItem(content: text("bad"), source: nil, at: t0))
        queue.yield(CaptureItem(content: text("good"), source: nil, at: t0.addingTimeInterval(1)))
        queue.finish()
        await task.value
        #expect(await log.events == [.writeFailed])
        #expect(try previews(f.writer) == ["good"])
    }
}
