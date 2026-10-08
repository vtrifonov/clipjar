import os

/// Never log clip content, previews, clip file paths or content hashes.
public enum Log {
    public static let capture = Logger(subsystem: "com.vtrifonov.clipjar", category: "capture")
    public static let store = Logger(subsystem: "com.vtrifonov.clipjar", category: "store")
    public static let paste = Logger(subsystem: "com.vtrifonov.clipjar", category: "paste")
    public static let panel = Logger(subsystem: "com.vtrifonov.clipjar", category: "panel")
    public static let hotkey = Logger(subsystem: "com.vtrifonov.clipjar", category: "hotkey")
}
