import AppKit
import ClipjarCore
import QuartzCore
import SwiftUI

/// Borderless, non-activating panel that can still take keyboard focus for the search field.
final class ClipjarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows the history panel over the frontmost app without activating Clipjar, so the app the user was
/// in stays active and receives the paste.
final class PanelController: NSObject, NSWindowDelegate {
    private static let openDuration: TimeInterval = 0.12
    private static let closeDuration: TimeInterval = 0.08
    private static let openScale: CGFloat = 0.97

    private let model: HistoryViewModel
    private let settings: SettingsStore
    private let paster: Paster
    private let statusButtonFrame: () -> NSRect?
    private let restoreFocus: () -> Void
    private let panel: ClipjarPanel

    /// The app that was frontmost when the panel opened; paste goes back to it. nil when that was Clipjar.
    private var target: SourceAppHandle?
    private var isShown = false
    private var isHidingImmediately = false
    /// Bumped on every show, so a fade-out that finishes after a reopen leaves the panel up.
    private var showGeneration = 0
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    init(
        model: HistoryViewModel,
        settings: SettingsStore,
        paster: Paster,
        statusButtonFrame: @escaping () -> NSRect?,
        restoreFocus: @escaping () -> Void
    ) {
        self.model = model
        self.settings = settings
        self.paster = paster
        self.statusButtonFrame = statusButtonFrame
        self.restoreFocus = restoreFocus
        panel = ClipjarPanel(
            contentRect: NSRect(origin: .zero, size: PanelPlacement.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: HistoryView(model: model, settings: settings))
        hosting.wantsLayer = true
        panel.contentView = hosting
        panel.delegate = self
    }

    var isVisible: Bool { isShown }

    func toggle(_ placement: OpenPlacement) {
        if isShown {
            hide()
        } else {
            show(placement)
        }
    }

    func show(_ placement: OpenPlacement) {
        target = FocusTracker.pasteTarget(
            frontmost: NSWorkspace.shared.frontmostApplication.map(SourceAppHandle.init),
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
        let frame = frame(for: placement)
        showGeneration += 1
        isShown = true
        model.prepareForOpen()
        if let frame { panel.setFrame(frame, display: false) }

        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animate ? 0 : 1
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        guard animate else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.openDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        if let layer = panel.contentView?.layer {
            let grow = CABasicAnimation(keyPath: "transform")
            grow.fromValue = NSValue(caTransform3D: Self.topAnchoredScale(Self.openScale, in: layer.bounds))
            grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            grow.duration = Self.openDuration
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(grow, forKey: "open")
        }
    }

    /// Fades out. If Clipjar is the active app, focus goes back to the target, or to the last other app when
    /// the panel opened with no target (e.g. after a Finder reopen).
    func hide() {
        guard isShown else { return }
        isShown = false
        model.commitPendingDeletion()
        removeMonitors()
        let generation = showGeneration
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finishHide(generation)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.closeDuration
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.finishHide(generation) }
            }
        }
        guard NSApp.isActive else { return }
        if let target {
            _ = SystemAppActivator().activate(target)
        } else {
            restoreFocus()
        }
    }

    private func finishHide(_ generation: Int) {
        guard generation == showGeneration else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    /// Paste/copy path: no fade, and returns once the panel has given up key status.
    func hideImmediately() async {
        isHidingImmediately = true
        defer { isHidingImmediately = false }
        isShown = false
        showGeneration += 1
        model.commitPendingDeletion()
        removeMonitors()
        panel.orderOut(nil)
        panel.alphaValue = 1
        let deadline = ContinuousClock.now + .milliseconds(100)
        while panel.isKeyWindow, ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    func paste(id: Int64, copyOnly: Bool) {
        let target = target
        Task {
            let outcome = await paster.perform(
                clipID: id,
                target: target,
                copyOnly: copyOnly,
                pasteOnSelect: settings.pasteOnSelect,
                closePanel: { await self.hideImmediately() }
            )
            Log.paste.info("outcome \(String(describing: outcome), privacy: .public)")
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard !isHidingImmediately else { return }
        hide()
    }

    // MARK: Placement

    private func frame(for placement: OpenPlacement) -> NSRect? {
        switch placement {
        case .statusItem:
            guard let button = statusButtonFrame(),
                  let screen = NSScreen.screens.first(where: { $0.frame.intersects(button) }) ?? NSScreen.main
            else { return frame(for: .cursor) }
            return PanelPlacement.belowStatusItem(buttonFrame: button, visibleFrame: screen.visibleFrame)
        case .cursor:
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
            else { return nil }
            return PanelPlacement.nearCursor(mouse, visibleFrame: screen.visibleFrame)
        case .centred:
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
            return PanelPlacement.centred(visibleFrame: screen.visibleFrame)
        }
    }

    /// Scale about the top-centre of a layer whose anchor point is its bottom-left corner.
    private static func topAnchoredScale(_ s: CGFloat, in bounds: CGRect) -> CATransform3D {
        var t = CATransform3DMakeScale(s, s, 1)
        t.m41 = bounds.midX * (1 - s)
        t.m42 = bounds.maxY * (1 - s)
        return t
    }

    // MARK: Event monitors

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return consumed ? nil : event
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }

    /// True when the panel consumed the key. Keys typed into an input method's marked text pass through.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        let deleteToastVisible = if case .deleted = model.toast { true } else { false }
        guard let cmd = PanelKeyMap.command(
            for: event.keyCode, modifiers: event.modifierFlags, deleteToastVisible: deleteToastVisible
        ) else { return false }
        return model.handle(cmd)
    }
}
