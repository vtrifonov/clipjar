import AppKit
import ClipjarCore
import KeyboardShortcuts
import Observation

/// The menu bar icon: left click toggles the panel, right or control click shows the menu.
final class StatusItemController: NSObject {
    private let settings: SettingsStore
    private let onToggle: () -> Void
    private let onOpen: () -> Void
    private let onOpenSettings: () -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let pauseItem = NSMenuItem()
    private let openItem = NSMenuItem()

    init(
        settings: SettingsStore,
        onToggle: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.settings = settings
        self.onToggle = onToggle
        self.onOpen = onOpen
        self.onOpenSettings = onOpenSettings
        super.init()

        if let button = item.button {
            let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipjar")?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        buildMenu()
        track()
    }

    var buttonScreenFrame: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// A short dip in opacity on each capture; nothing under Reduce Motion.
    func pulse() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let button = item.button else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            button.animator().alphaValue = 0.35
        } completionHandler: {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    button.animator().alphaValue = 1
                }
            }
        }
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        } else {
            onToggle()
        }
    }

    private func buildMenu() {
        openItem.title = "Open Clipjar"
        openItem.action = #selector(openClicked)
        openItem.target = self
        openItem.setShortcut(for: .togglePanel)
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("Pause for 15 Minutes", #selector(pauseBrieflyClicked)))
        pauseItem.action = #selector(pauseToggleClicked)
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(settingsClicked), key: ","))
        menu.addItem(menuItem("Quit Clipjar", #selector(quitClicked), key: "q"))
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Re-registers on every change, so the button follows the pause state.
    private func track() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.track() }
        }
    }

    private func refresh() {
        let paused = settings.isPaused
        pauseItem.title = paused ? "Resume" : "Pause"
        item.button?.appearsDisabled = paused
        item.button?.toolTip = paused ? "Clipjar — paused" : "Clipjar"
    }

    @objc private func openClicked() { onOpen() }
    @objc private func pauseBrieflyClicked() { settings.pause(for: 900) }
    @objc private func settingsClicked() { onOpenSettings() }
    @objc private func quitClicked() { NSApp.terminate(nil) }

    @objc private func pauseToggleClicked() {
        if settings.isPaused {
            settings.resume()
        } else {
            settings.pause(for: nil)
        }
    }
}
