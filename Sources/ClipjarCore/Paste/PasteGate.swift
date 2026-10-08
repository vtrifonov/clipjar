/// One paste at a time: a second ⏎, ⌘1 or click while a paste is still running is ignored, so ⌘V is
/// posted exactly once.
public struct PasteGate: Sendable {
    public private(set) var isBusy = false

    public init() {}

    /// True when the caller may start a paste; it must call `end()` when the paste finishes.
    public mutating func begin() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    public mutating func end() {
        isBusy = false
    }
}
