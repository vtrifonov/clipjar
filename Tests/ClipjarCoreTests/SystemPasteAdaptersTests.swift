import AppKit
import Testing
@testable import ClipjarCore

/// Event posting and real activation are verified manually.
@MainActor @Suite struct SystemPasteAdaptersTests {
    /// `NSRunningApplication.current` reports pid -1 in the test runner (it is not a registered app),
    /// so the mapping is checked against another running application.
    @Test func handleFromRunningApplication() throws {
        let app = try #require(NSWorkspace.shared.runningApplications.first { $0.processIdentifier > 0 })
        let handle = SourceAppHandle(app)
        #expect(handle.pid == app.processIdentifier)
        #expect(handle.bundleID == app.bundleIdentifier)
    }

    @Test func activateUnknownPidFails() {
        #expect(SystemAppActivator().activate(SourceAppHandle(bundleID: nil, pid: 999_999)) == false)
    }
}
