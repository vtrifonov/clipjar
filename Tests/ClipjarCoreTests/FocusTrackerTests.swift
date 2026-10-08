import Testing
@testable import ClipjarCore

@Suite struct FocusTrackerTests {
    private let own = SourceAppHandle(bundleID: AppIdentity.bundleID, pid: 100)
    private let editor = SourceAppHandle(bundleID: "com.example.editor", pid: 200)
    private let browser = SourceAppHandle(bundleID: "com.example.browser", pid: 300)

    @Test func pasteTargetIsTheFrontmostOtherApp() {
        #expect(FocusTracker.pasteTarget(frontmost: editor, ownPID: own.pid) == editor)
    }

    @Test func noPasteTargetWhenClipjarIsFrontmost() {
        #expect(FocusTracker.pasteTarget(frontmost: own, ownPID: own.pid) == nil)
        #expect(FocusTracker.pasteTarget(frontmost: nil, ownPID: own.pid) == nil)
    }

    @Test func remembersTheLastOtherAppActivated() {
        var tracker = FocusTracker(ownPID: own.pid)
        #expect(tracker.lastExternalApp == nil)
        let first = tracker.appActivated(editor)
        let second = tracker.appActivated(browser)
        #expect(first && second)
        #expect(tracker.lastExternalApp == browser)
    }

    @Test func ownActivationIsIgnored() {
        var tracker = FocusTracker(ownPID: own.pid)
        _ = tracker.appActivated(editor)
        let closesPanel = tracker.appActivated(own)
        #expect(!closesPanel)
        #expect(tracker.lastExternalApp == editor)
    }
}
