import AppKit

/// Panel shortcuts. Never claims ⌘A/⌘C/⌘V/⌘X (left to the search field); ⌘Z only while the delete toast shows.
public enum PanelKeyMap {
    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
    /// Key codes for 1...9 on the main keyboard row.
    private static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    public static func command(
        for keyCode: UInt16, modifiers: NSEvent.ModifierFlags, deleteToastVisible: Bool
    ) -> PanelCommand? {
        // Arrow keys also carry .numericPad and .function.
        let mods = modifiers.intersection(relevantModifiers)
        switch (keyCode, mods) {
        case (126, []): return .moveUp
        case (125, []): return .moveDown
        case (126, [.command]): return .moveToTop
        case (125, [.command]): return .moveToBottom
        case (116, []): return .pageUp
        case (121, []): return .pageDown
        case (36, []), (76, []): return .activate(copyOnly: false)
        case (36, [.option]): return .activate(copyOnly: true)
        case (35, [.command]): return .togglePin
        case (51, [.command]): return .delete
        case (6, [.command]): return deleteToastVisible ? .undoDelete : nil
        case (48, []): return .nextFilter
        case (48, [.shift]): return .previousFilter
        case (53, []): return .escape
        case (43, [.command]): return .openSettings
        case (13, [.command]), (12, [.command]): return .close
        case (_, [.command]):
            return digitKeyCodes.firstIndex(of: keyCode).map { .activateRow($0 + 1) }
        default: return nil
        }
    }
}
