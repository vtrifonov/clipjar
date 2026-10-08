public enum PanelCommand: Equatable, Sendable {
    case moveUp, moveDown, moveToTop, moveToBottom, pageUp, pageDown
    /// `row` is 1...9.
    case activate(copyOnly: Bool), activateRow(Int), togglePin, delete, undoDelete
    case nextFilter, previousFilter, escape, close, openSettings
}
