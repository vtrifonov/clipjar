import Foundation
@testable import ClipjarCore

@MainActor final class EventLog {
    private(set) var events: [String] = []

    func add(_ e: String) {
        events.append(e)
    }
}

@MainActor final class FakeAX: AccessibilityChecking {
    var trusted = true

    func isTrusted() -> Bool { trusted }
}

/// Logs "cmdV".
@MainActor final class FakeKeyPoster: KeyEventPosting {
    var posts = 0
    let log: EventLog

    init(log: EventLog) {
        self.log = log
    }

    func postCommandV() {
        posts += 1
        log.add("cmdV")
    }
}

/// `activate` logs "activate". `frontmostScript` is consumed one value per call; the last value repeats.
@MainActor final class FakeApps: AppActivating {
    var activateResult = true
    var frontmostScript: [pid_t?] = []
    private(set) var beeps = 0
    let log: EventLog

    init(log: EventLog) {
        self.log = log
    }

    func activate(_ app: SourceAppHandle) -> Bool {
        log.add("activate")
        return activateResult
    }

    func frontmostPID() -> pid_t? {
        guard let first = frontmostScript.first else { return nil }
        if frontmostScript.count > 1 { frontmostScript.removeFirst() }
        return first
    }

    func beep() {
        beeps += 1
    }
}
