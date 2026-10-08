import Darwin
import Foundation

/// Holds an exclusive `flock` on `<support>/.lock` for its lifetime; deinit closes the fd, releasing it.
public final class InstanceLock: Sendable {
    public enum Result: Sendable { case acquired(InstanceLock), heldByOther, failed(Int32 /* errno */) }

    private let fd: Int32

    private init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        close(fd)
    }

    /// Creates `supportDirectory` (0700) if needed, opens `<support>/.lock` (O_RDWR|O_CREAT|O_CLOEXEC, 0600),
    /// flock(LOCK_EX|LOCK_NB). EWOULDBLOCK → .heldByOther; any other failure → .failed(errno).
    public static func acquire(supportDirectory: URL) -> Result {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: supportDirectory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { return .failed(ENOTDIR) }
        } else {
            do {
                try fm.createDirectory(
                    at: supportDirectory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
                let code = underlying?.domain == NSPOSIXErrorDomain ? Int32(underlying?.code ?? Int(EIO)) : EIO
                return .failed(code)
            }
        }

        let path = supportDirectory.appendingPathComponent(".lock").path
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { return .failed(errno) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            return code == EWOULDBLOCK ? .heldByOther : .failed(code)
        }
        return .acquired(InstanceLock(fd: fd))
    }
}
