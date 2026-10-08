import Foundation
import Testing
@testable import ClipjarCore

@MainActor @Suite struct ClipboardWatcherTests {
    private static let onePassword = SourceApp(bundleID: "com.1password.1password", name: "1Password")
    private static let clipjar = SourceApp(bundleID: AppIdentity.bundleID, name: "Clipjar")

    /// Mutable environment captured by the watcher's closures.
    @MainActor final class Harness {
        let pb = FakePasteboard()
        var settings = FilterSettings()
        var front: SourceApp? = textEdit
        var running: [String: String] = [:]
        var now = t0
        var sinkCalls: [(CapturedContent, SourceApp?, Date)] = []
        var captures = 0
        private(set) var watcher: ClipboardWatcher!

        init() {
            watcher = ClipboardWatcher(
                pasteboard: pb,
                settings: { [unowned self] in settings },
                frontmostApp: { [unowned self] in front },
                runningAppName: { [unowned self] in running[$0] },
                ownBundleID: AppIdentity.bundleID,
                clock: { [unowned self] in now },
                sink: { [unowned self] in sinkCalls.append(($0, $1, $2)) }
            )
            watcher.onCapture = { [unowned self] in captures += 1 }
        }

        func copyText(_ s: String, extra: Set<String> = [], declared: String? = nil) {
            pb.copy(types: extra.union([PasteboardTypes.string]), string: s, declared: declared)
        }
    }

    @Test func launchCaptureOnFirstPoll() {
        let h = Harness()
        h.pb.copy(types: [PasteboardTypes.string], string: "Hello, Clipjar")
        h.pb.changeCount = 5
        h.watcher.poll()
        #expect(h.sinkCalls.count == 1)
        #expect(h.sinkCalls.first?.0 == CapturedContent(kind: .text, plainText: "Hello, Clipjar"))
    }

    @Test func noChangeNoSink() {
        let h = Harness()
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        h.watcher.poll()
        #expect(h.sinkCalls.count == 1)
    }

    @Test func copyCapturedOnce() {
        let h = Harness()
        h.watcher.poll()
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        h.watcher.poll()
        #expect(h.sinkCalls.count == 1)
    }

    @Test func pausedReadsNoData() {
        let h = Harness()
        h.settings.isPaused = true
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        #expect(h.sinkCalls.isEmpty)
        #expect(h.pb.totalDataReads == 0)
    }

    @Test func ignoredFrontmostReadsNoData() {
        let h = Harness()
        h.front = Self.onePassword
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        #expect(h.sinkCalls.isEmpty)
        #expect(h.pb.totalDataReads == 0)
    }

    @Test func concealedReadsNoData() {
        let h = Harness()
        h.copyText("Hello, Clipjar", extra: [PasteboardTypes.concealed])
        h.watcher.poll()
        #expect(h.sinkCalls.isEmpty)
        #expect(h.pb.totalDataReads == 0)
    }

    @Test func markerReadsNoData() {
        let h = Harness()
        h.copyText("Hello, Clipjar", extra: [PasteboardTypes.marker])
        h.watcher.poll()
        #expect(h.sinkCalls.isEmpty)
        #expect(h.pb.totalDataReads == 0)
    }

    @Test func pausedContentNotCapturedAfterResume() {
        let h = Harness()
        h.settings.isPaused = true
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        h.settings.isPaused = false
        h.watcher.poll()
        #expect(h.sinkCalls.isEmpty)
    }

    @Test func declaredSourcePreferredWhenRunning() throws {
        let h = Harness()
        h.running["com.example.editor"] = "Editor"
        h.copyText("Hello, Clipjar", declared: "com.example.editor")
        h.watcher.poll()
        let call = try #require(h.sinkCalls.first)
        #expect(call.1 == SourceApp(bundleID: "com.example.editor", name: "Editor"))
    }

    @Test func declaredSourceNotRunningFallsBackToFrontmost() throws {
        let h = Harness()
        h.copyText("Hello, Clipjar", declared: "com.example.editor")
        h.watcher.poll()
        let call = try #require(h.sinkCalls.first)
        #expect(call.1 == textEdit)
    }

    @Test func clipjarFrontmostIsNotCaptured() {
        let h = Harness()
        h.front = Self.clipjar
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        #expect(h.sinkCalls.isEmpty)
        #expect(ClipboardWatcher.attributedSource(declared: nil, frontmost: Self.clipjar, ownBundleID: AppIdentity.bundleID) == nil)
    }

    @Test func attributedSourcePrefersDeclared() {
        let editor = SourceApp(bundleID: "com.example.editor", name: "Editor")
        #expect(ClipboardWatcher.attributedSource(declared: editor, frontmost: textEdit, ownBundleID: AppIdentity.bundleID) == editor)
        #expect(ClipboardWatcher.attributedSource(declared: nil, frontmost: textEdit, ownBundleID: AppIdentity.bundleID) == textEdit)
        #expect(ClipboardWatcher.attributedSource(declared: nil, frontmost: nil, ownBundleID: AppIdentity.bundleID) == nil)
    }

    @Test func ignoredActivatedWithinTickRejected() {
        let h = Harness()
        h.front = safari
        h.watcher.poll()
        h.watcher.appActivated(Self.onePassword)
        h.watcher.appActivated(textEdit)
        h.front = textEdit
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        #expect(h.sinkCalls.isEmpty)
    }

    @Test func ignoredFrontmostAtLastTickRejected() {
        let h = Harness()
        h.front = Self.onePassword
        h.watcher.poll()
        h.front = textEdit
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        #expect(h.sinkCalls.isEmpty)
    }

    @Test func staleActivationClearedAfterIdleTick() {
        let h = Harness()
        h.watcher.poll()
        h.watcher.appActivated(Self.onePassword)
        h.watcher.poll()
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        #expect(h.sinkCalls.count == 1)
    }

    @Test func oversizedNotCaptured() {
        let h = Harness()
        h.copyText(String(repeating: "a", count: 1_000_001))
        h.watcher.poll()
        #expect(h.sinkCalls.isEmpty)
    }

    @Test func onCaptureCalled() {
        let h = Harness()
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        #expect(h.captures == 1)
    }

    @Test func sinkReceivesClockTime() throws {
        let h = Harness()
        h.now = t0
        h.copyText("Hello, Clipjar")
        h.watcher.poll()
        #expect(try #require(h.sinkCalls.first).2 == t0)
    }

    @Test func startPollsImmediately() async throws {
        let h = Harness()
        h.copyText("Hello, Clipjar")
        h.watcher.start(interval: .seconds(60))
        defer { h.watcher.stop() }
        for _ in 0 ..< 100 where h.sinkCalls.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(h.sinkCalls.count == 1)
    }
}
