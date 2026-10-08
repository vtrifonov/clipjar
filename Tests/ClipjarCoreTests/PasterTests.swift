import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@MainActor @Suite struct PasterTests {
    private static let pid: pid_t = 4242
    private static let target = SourceAppHandle(bundleID: "com.apple.TextEdit", pid: pid)
    private static let pasteTime = t0.addingTimeInterval(100)

    @MainActor final class SleepLog {
        private(set) var durations: [Duration] = []
        nonisolated init() {}
        func record(_ d: Duration) { durations.append(d) }
    }

    @MainActor final class Harness {
        let fx: StoreFixture
        let log = EventLog()
        let pb = FakePasteboard()
        let ax = FakeAX()
        let keys: FakeKeyPoster
        let apps: FakeApps
        let sleeps = SleepLog()
        let paster: Paster
        var clipID: Int64 = 0

        init() async throws {
            fx = try makeStore(.memoryQueue)
            keys = FakeKeyPoster(log: log)
            apps = FakeApps(log: log)
            apps.frontmostScript = [PasterTests.pid]
            let sleeps = sleeps
            paster = Paster(
                store: fx.store, pasteboard: pb, ax: ax, keys: keys, apps: apps,
                sleep: { await sleeps.record($0) }, clock: { PasterTests.pasteTime }
            )
            pb.onWrite = { [log] in log.add("write") }
            let result = try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0)
            guard case let .inserted(id) = result else { throw CancellationError() }
            clipID = id
        }

        func perform(
            id: Int64? = nil, target: SourceAppHandle? = PasterTests.target, copyOnly: Bool = false,
            pasteOnSelect: Bool = true
        ) async -> PasteOutcome {
            await paster.perform(
                clipID: id ?? clipID, target: target, copyOnly: copyOnly, pasteOnSelect: pasteOnSelect,
                closePanel: { [log] in log.add("close") }
            )
        }
    }

    @Test func trustedPastePostsOnceInOrder() async throws {
        let h = try await Harness()
        #expect(await h.perform() == .pasted)
        #expect(h.log.events == ["write", "close", "activate", "cmdV"])
        #expect(h.keys.posts == 1)
        #expect(h.pb.written == [.text(plain: "Hello, Clipjar", rtf: nil, html: nil)])
        #expect(h.sleeps.durations == [.milliseconds(40)])
    }

    @Test func copyOnlyNeverPosts() async throws {
        let h = try await Harness()
        #expect(await h.perform(copyOnly: true) == .copiedOnly(.userRequested))
        #expect(h.keys.posts == 0)
        #expect(h.pb.written.count == 1)
        #expect(!h.log.events.contains("activate"))
        #expect(h.log.events == ["write", "close"])
    }

    @Test func pasteDisabled() async throws {
        let h = try await Harness()
        #expect(await h.perform(pasteOnSelect: false) == .copiedOnly(.pasteDisabled))
        #expect(h.keys.posts == 0)
        #expect(h.pb.written.count == 1)
    }

    @Test func notTrusted() async throws {
        let h = try await Harness()
        h.ax.trusted = false
        #expect(await h.perform() == .copiedOnly(.notTrusted))
        #expect(h.keys.posts == 0)
        #expect(h.pb.written.count == 1)
    }

    @Test func nilTarget() async throws {
        let h = try await Harness()
        #expect(await h.perform(target: nil) == .copiedOnly(.targetUnavailable))
        #expect(h.keys.posts == 0)
        #expect(h.pb.written.count == 1)
    }

    @Test func activateFails() async throws {
        let h = try await Harness()
        h.apps.activateResult = false
        #expect(await h.perform() == .copiedOnly(.targetUnavailable))
        #expect(h.keys.posts == 0)
        #expect(h.log.events == ["write", "close", "activate"])
    }

    @Test func frontmostTimeoutNeverPosts() async throws {
        let h = try await Harness()
        h.apps.frontmostScript = [999]
        #expect(await h.perform() == .copiedOnly(.targetUnavailable))
        #expect(h.keys.posts == 0)
        #expect(h.sleeps.durations == Array(repeating: .milliseconds(10), count: 25))
        #expect(!h.sleeps.durations.contains(.milliseconds(40)))
    }

    @Test func frontmostEventuallyMatches() async throws {
        let h = try await Harness()
        h.apps.frontmostScript = [999, 999, Self.pid]
        #expect(await h.perform() == .pasted)
        #expect(h.keys.posts == 1)
        #expect(h.sleeps.durations == [.milliseconds(10), .milliseconds(10), .milliseconds(40)])
    }

    @Test func frontmostLostDuringSettle() async throws {
        let h = try await Harness()
        h.apps.frontmostScript = [Self.pid, 999]
        #expect(await h.perform() == .copiedOnly(.targetUnavailable))
        #expect(h.keys.posts == 0)
    }

    @Test func missingPayloadWritesNothing() async throws {
        let h = try await Harness()
        #expect(await h.perform(id: 987_654) == .copiedOnly(.userRequested))
        #expect(h.pb.written.isEmpty)
        #expect(h.apps.beeps == 1)
        #expect(!h.log.events.contains("close"))
        #expect(h.keys.posts == 0)
    }

    @Test func touchUpdatesRecency() async throws {
        let h = try await Harness()
        #expect(await h.perform() == .pasted)
        var touched = false
        for _ in 0 ..< 100 {
            if try await h.fx.store.clip(id: h.clipID)?.lastCopiedAt == Self.pasteTime {
                touched = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(touched)
    }

    @Test func touchFailureDoesNotChangeOutcome() async throws {
        let h = try await Harness()
        try await h.fx.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER no_update BEFORE UPDATE ON clip BEGIN SELECT RAISE(ABORT, 'x'); END")
        }
        #expect(await h.perform() == .pasted)
        #expect(h.keys.posts == 1)
    }
}
