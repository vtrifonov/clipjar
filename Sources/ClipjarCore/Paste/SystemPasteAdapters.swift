import AppKit
import ApplicationServices

/// Accessibility is used solely to post ⌘V.
@MainActor public final class SystemAccessibility: AccessibilityChecking {
    public init() {}

    public func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt. The string key avoids the non-Sendable `kAXTrustedCheckOptionPrompt` global.
    public func promptForTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

@MainActor public final class SystemKeyPoster: KeyEventPosting {
    private static let vKey: CGKeyCode = 0x09

    public init() {}

    public func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: Self.vKey, keyDown: keyDown) else {
                Log.paste.error("key event creation failed")
                return
            }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}

@MainActor public final class SystemAppActivator: AppActivating {
    public init() {}

    public func activate(_ app: SourceAppHandle) -> Bool {
        guard let running = NSRunningApplication(processIdentifier: app.pid), !running.isTerminated else { return false }
        if NSApp?.isActive == true {
            return running.activate(from: .current, options: [])
        }
        return running.activate(options: [])
    }

    public func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    public func beep() {
        NSSound.beep()
    }
}

extension SourceAppHandle {
    public init(_ app: NSRunningApplication) {
        self.init(bundleID: app.bundleIdentifier, pid: app.processIdentifier)
    }
}
