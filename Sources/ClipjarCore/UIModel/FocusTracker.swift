import Foundation

/// Which app a paste goes to, and which app gets focus back when Clipjar steps aside. Clipjar itself
/// (matched by pid, so an unbundled build counts too) is never either.
public struct FocusTracker: Sendable {
    public let ownPID: pid_t
    public private(set) var lastExternalApp: SourceAppHandle?

    public init(ownPID: pid_t) {
        self.ownPID = ownPID
    }

    /// The app frontmost when the panel opens, unless that is Clipjar: a paste then only copies.
    public static func pasteTarget(frontmost: SourceAppHandle?, ownPID: pid_t) -> SourceAppHandle? {
        guard let frontmost, frontmost.pid != ownPID else { return nil }
        return frontmost
    }

    /// True when another app became active, which also closes the panel.
    public mutating func appActivated(_ app: SourceAppHandle) -> Bool {
        guard app.pid != ownPID else { return false }
        lastExternalApp = app
        return true
    }
}
