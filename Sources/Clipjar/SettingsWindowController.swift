import AppKit
import ClipjarCore
import SwiftUI

/// The Settings window, created once and reused.
final class SettingsWindowController {
    private let window: NSWindow
    private var hasBeenShown = false

    init(settings: SettingsStore, store: ClipStore, retention: RetentionChanger) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, store: store, retention: retention))
        hosting.sizingOptions = .preferredContentSize
        window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Clipjar Settings"
        window.isReleasedWhenClosed = false
    }

    /// Activates Clipjar so the window takes focus; centred only the first time.
    func show() {
        NSApp.activate()
        if !hasBeenShown {
            window.center()
            hasBeenShown = true
        }
        window.makeKeyAndOrderFront(nil)
    }
}
