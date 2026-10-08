import Foundation

@MainActor public protocol AccessibilityChecking {
    func isTrusted() -> Bool
}

@MainActor public protocol KeyEventPosting {
    func postCommandV()
}

public struct SourceAppHandle: Sendable, Equatable {
    public var bundleID: String?
    public var pid: pid_t

    public init(bundleID: String?, pid: pid_t) {
        self.bundleID = bundleID
        self.pid = pid
    }
}

@MainActor public protocol AppActivating {
    func activate(_ app: SourceAppHandle) -> Bool
    func frontmostPID() -> pid_t?
    func beep()
}

public enum PasteOutcome: Equatable, Sendable {
    case pasted
    case copiedOnly(CopyReason)

    public enum CopyReason: Sendable { case userRequested, pasteDisabled, notTrusted, targetUnavailable }
}

/// Writes a clip to the pasteboard, closes the panel, then posts exactly one ⌘V into the target app
/// only once it is verifiably frontmost. Any other path leaves the clip on the pasteboard without pasting.
@MainActor public final class Paster {
    private let store: ClipStore
    private let pasteboard: PasteboardWriting
    private let ax: AccessibilityChecking
    private let keys: KeyEventPosting
    private let apps: AppActivating
    private let sleep: @Sendable (Duration) async -> Void
    private let clock: @MainActor () -> Date

    public init(
        store: ClipStore,
        pasteboard: PasteboardWriting,
        ax: AccessibilityChecking,
        keys: KeyEventPosting,
        apps: AppActivating,
        sleep: @escaping @Sendable (Duration) async -> Void,
        clock: @escaping @MainActor () -> Date = Date.init
    ) {
        self.store = store
        self.pasteboard = pasteboard
        self.ax = ax
        self.keys = keys
        self.apps = apps
        self.sleep = sleep
        self.clock = clock
    }

    public func perform(
        clipID: Int64,
        target: SourceAppHandle?,
        copyOnly: Bool,
        pasteOnSelect: Bool,
        closePanel: @MainActor () async -> Void
    ) async -> PasteOutcome {
        let payload: ClipPayload
        do {
            guard let p = try await store.payload(id: clipID) else {
                apps.beep()
                return .copiedOnly(.userRequested)
            }
            payload = p
        } catch {
            let e = error as NSError
            Log.paste.error("payload read failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            apps.beep()
            return .copiedOnly(.userRequested)
        }

        pasteboard.write(payload)
        await closePanel()

        // Recency update is fire-and-forget; its failure never changes the outcome.
        let store = self.store
        let now = clock()
        Task {
            do {
                try await store.touch(id: clipID, at: now)
            } catch {
                let e = error as NSError
                Log.paste.error("touch failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            }
        }

        if copyOnly { return .copiedOnly(.userRequested) }
        if !pasteOnSelect { return .copiedOnly(.pasteDisabled) }
        if !ax.isTrusted() { return .copiedOnly(.notTrusted) }
        guard let target else { return .copiedOnly(.targetUnavailable) }
        guard apps.activate(target) else { return .copiedOnly(.targetUnavailable) }

        var waited = 0
        while apps.frontmostPID() != target.pid {
            if waited >= 250 {
                Log.paste.warning("target not frontmost")
                return .copiedOnly(.targetUnavailable)
            }
            await sleep(.milliseconds(10))
            waited += 10
        }
        await sleep(.milliseconds(40))
        guard apps.frontmostPID() == target.pid else { return .copiedOnly(.targetUnavailable) }
        keys.postCommandV()
        return .pasted
    }
}
