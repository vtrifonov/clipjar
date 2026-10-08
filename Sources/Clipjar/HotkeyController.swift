import ClipjarCore
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Stored by KeyboardShortcuts under `KeyboardShortcuts_togglePanel`; cleared means no global hotkey.
    static let togglePanel = Self("togglePanel", initial: .init(.v, modifiers: [.command, .shift]))
}

/// Registers the global hotkey that opens and closes the panel.
final class HotkeyController {
    init(onTrigger: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { onTrigger() }
        Log.hotkey.debug("hotkey handler registered, shortcut set: \(KeyboardShortcuts.getShortcut(for: .togglePanel) != nil)")
    }

    /// Shown in the panel header; nil hides the hint.
    static var currentShortcutDescription: String? {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description
    }
}
