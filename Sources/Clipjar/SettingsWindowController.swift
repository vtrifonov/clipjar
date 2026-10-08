import AppKit
import ClipjarCore
import SwiftUI

/// The Settings window, created once and reused.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onClose: () -> Void
    private var hasBeenShown = false

    /// `onClose` runs when the window closes, so focus can go back to the app the user came from.
    init(
        settings: SettingsStore,
        store: ClipStore,
        retention: RetentionChanger,
        storeErrors: StoreErrorReporter,
        onClose: @escaping () -> Void
    ) {
        let hosting = NSHostingController(rootView: SettingsView(
            settings: settings, store: store, retention: retention, storeErrors: storeErrors
        ))
        hosting.sizingOptions = .preferredContentSize
        window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Clipjar Settings"
        window.isReleasedWhenClosed = false
        self.onClose = onClose
        super.init()
        window.delegate = self
    }

    var isVisible: Bool { window.isVisible }

    /// Activates Clipjar so the window takes focus; centred only the first time.
    func show() {
        NSApp.activate()
        if !hasBeenShown {
            window.center()
            hasBeenShown = true
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
