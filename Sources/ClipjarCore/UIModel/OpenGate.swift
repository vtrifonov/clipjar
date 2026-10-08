public enum OpenPlacement: Equatable, Sendable { case statusItem, cursor, centred }

/// Holds panel open requests made before the app is ready; only the latest is kept and replayed once.
public struct OpenGate: Sendable {
    public private(set) var isReady = false
    private var queued: OpenPlacement?

    public init() {}

    /// Ready → `p`; otherwise queues it (latest wins) and returns nil.
    public mutating func request(_ p: OpenPlacement) -> OpenPlacement? {
        if isReady { return p }
        queued = p
        return nil
    }

    /// Marks the gate ready and returns the queued request, at most once.
    public mutating func markReady() -> OpenPlacement? {
        isReady = true
        defer { queued = nil }
        return queued
    }
}
