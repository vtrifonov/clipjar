import Foundation
import Testing
@testable import ClipjarCore

@Suite struct InstanceLockTests {
    private func supportURL(_ dir: TempDir) -> URL {
        dir.url.appendingPathComponent("Support", isDirectory: true)
    }

    @Test func acquireSucceedsAndCreatesFiles() throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        let result = InstanceLock.acquire(supportDirectory: support)
        guard case .acquired = result else {
            Issue.record("expected .acquired, got \(result)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent(".lock").path))
        #expect(try posixPermissions(support) == 0o700)
    }

    @Test func secondAcquireIsHeldByOther() throws {
        let dir = try TempDir()
        let first = InstanceLock.acquire(supportDirectory: supportURL(dir))
        guard case .acquired = first else {
            Issue.record("expected .acquired, got \(first)")
            return
        }
        let second = InstanceLock.acquire(supportDirectory: supportURL(dir))
        guard case .heldByOther = second else {
            Issue.record("expected .heldByOther, got \(second)")
            return
        }
        withExtendedLifetime(first) {}
    }

    @Test func releasedOnDeinit() throws {
        let dir = try TempDir()
        var first: InstanceLock.Result? = InstanceLock.acquire(supportDirectory: supportURL(dir))
        guard case .acquired = first else {
            Issue.record("expected .acquired, got \(String(describing: first))")
            return
        }
        first = nil
        let again = InstanceLock.acquire(supportDirectory: supportURL(dir))
        guard case .acquired = again else {
            Issue.record("expected .acquired after release, got \(again)")
            return
        }
    }

    @Test func lockPathIsDirectoryFails() throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent(".lock", isDirectory: true), withIntermediateDirectories: true
        )
        let result = InstanceLock.acquire(supportDirectory: support)
        guard case .failed = result else {
            Issue.record("expected .failed, got \(result)")
            return
        }
    }

    @Test func supportPathIsRegularFileFails() throws {
        let dir = try TempDir()
        let support = supportURL(dir)
        try Data("synthetic".utf8).write(to: support)
        let result = InstanceLock.acquire(supportDirectory: support)
        guard case .failed = result else {
            Issue.record("expected .failed, got \(result)")
            return
        }
    }
}
