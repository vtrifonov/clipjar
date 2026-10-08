import Foundation
import GRDB

public enum StoreEvent: Sendable, Equatable { case writeFailed, corrupt }

public enum StoreErrorClassifier {
    /// Primary result code, so extended codes such as `SQLITE_CORRUPT_VTAB` count too.
    public static func isCorruption(_ error: any Error) -> Bool {
        (error as? DatabaseError)?.resultCode == .SQLITE_CORRUPT
    }

    /// Corruption → creates `<support>/.needs-repair` (empty, 0600) when supportDirectory != nil, returns .corrupt.
    /// Anything else → .writeFailed. Logs domain + code only.
    public static func classify(_ error: any Error, supportDirectory: URL?) -> StoreEvent {
        let e = error as NSError
        guard isCorruption(error) else {
            Log.store.error("store write failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            return .writeFailed
        }
        Log.store.error("store corruption: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
        if let supportDirectory {
            let flag = supportDirectory.appendingPathComponent(StoreOpener.repairFlagName).path
            if !FileManager.default.createFile(atPath: flag, contents: Data(), attributes: [.posixPermissions: 0o600]) {
                Log.store.error("repair flag write failed")
            }
        }
        return .corrupt
    }
}
