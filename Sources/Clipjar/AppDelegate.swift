import AppKit
import ApplicationServices
import ClipjarCore
import Observation

final class AppDelegate: NSObject, NSApplicationDelegate {
    let editActions = ClipjarEditActions()

    /// Held for the process lifetime; releasing it lets another instance open the store.
    private var lock: InstanceLock?
    private var settings: SettingsStore?
    private let captures = CaptureQueue()
    private var watcher: ClipboardWatcher?
    private var statusItem: StatusItemController?
    private var hotkey: HotkeyController?
    private var store: ClipStore?
    private var openResult: OpenResult?
    private var storeErrors: StoreErrorReporter?
    private var model: HistoryViewModel?
    private var panel: PanelController?
    private var settingsWindow: SettingsWindowController?
    /// Open requests made before the panel exists; replayed once it does.
    private var gate = OpenGate()
    /// Store events reported before the view model exists.
    private var bufferedEvents: [StoreEvent] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var captureActivity: NSObjectProtocol?
    /// The last other app the user was in; focus goes back to it when Clipjar steps aside.
    private var focus = FocusTracker(ownPID: ProcessInfo.processInfo.processIdentifier)

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Menu, so key equivalents work from the start.
        NSApp.mainMenu = MainMenu.build(editActions: editActions)

        // 2. One instance per support directory; a second bundled copy hands over to the first.
        let supportDir = try? StoreOpener.defaultSupportDirectory()
        if let supportDir {
            switch InstanceLock.acquire(supportDirectory: supportDir) {
            case let .acquired(l):
                lock = l
            case .heldByOther:
                if Bundle.main.bundleURL.pathExtension == "app" {
                    DistributedNotificationCenter.default().postNotificationName(
                        .init(AppIdentity.showNotification), object: nil, userInfo: nil, deliverImmediately: true
                    )
                    exit(0)
                }
                Log.store.info("store locked by another instance; using memory")
            case let .failed(code):
                Log.store.error("instance lock failed: errno \(code, privacy: .public)")
            }
        }

        // 3. Settings (re-arms a timed pause).
        let settings = SettingsStore(defaults: .standard)
        self.settings = settings

        // 4. Capture starts now; clips buffer in `captures` until the store is open.
        let captures = captures
        let watcher = ClipboardWatcher(
            pasteboard: SystemPasteboard(),
            settings: { settings.filterSettings },
            frontmostApp: {
                NSWorkspace.shared.frontmostApplication.map {
                    SourceApp(bundleID: $0.bundleIdentifier, name: $0.localizedName)
                }
            },
            runningAppName: { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.localizedName },
            ownBundleID: AppIdentity.bundleID,
            sink: { c, s, d in captures.yield(CaptureItem(content: c, source: s, at: d)) }
        )
        watcher.onCapture = { [weak self] in self?.statusItem?.pulse() }
        watcher.start()
        self.watcher = watcher

        // 5. Menu bar, hotkey and system observers.
        statusItem = StatusItemController(
            settings: settings,
            onToggle: { [weak self] in self?.requestOpen(.statusItem, toggle: true) },
            onOpen: { [weak self] in self?.requestOpen(.statusItem) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        hotkey = HotkeyController { [weak self] in self?.requestOpen(.cursor, toggle: true) }
        installObservers()
        if let front = NSWorkspace.shared.frontmostApplication { _ = focus.appActivated(SourceAppHandle(front)) }
        trackCaptureActivity()

        // 6–7. Open the store, start ingesting, then build the panel and replay any queued open.
        let useDisk = supportDir != nil && lock != nil
        Task {
            let result = if let supportDir, useDisk {
                await StoreOpener.open(supportDirectory: supportDir)
            } else {
                StoreOpener.openInMemory()
            }
            let store = result.store
            self.store = store
            openResult = result
            // Corruption from any store call writes the repair flag and shows the banner.
            let storeErrors = StoreErrorReporter(supportDirectory: result.supportDirectory) { self.handle($0) }
            self.storeErrors = storeErrors
            await store.configure(limit: settings.historyLimit, maxAgeDays: settings.maxAgeDays)
            await storeErrors.reportIfStoreError {
                try await store.prune(limit: settings.historyLimit, maxAgeDays: settings.maxAgeDays, now: Date())
            }
            _ = captures.startConsuming(store: store, supportDirectory: result.supportDirectory) {
                self.handle($0)
            }
            // The sweep runs on the store actor, off the main thread.
            Task(priority: .utility) {
                await storeErrors.reportIfStoreError { try await store.cleanOrphanBlobs(now: Date()) }
            }

            buildPanel(store: store, result: result, settings: settings, storeErrors: storeErrors)
        }

        // 8. First launch shows the panel once, centred.
        if !settings.hasLaunchedBefore {
            settings.hasLaunchedBefore = true
            requestOpen(.centred)
        }
    }

    private func buildPanel(
        store: ClipStore, result: OpenResult, settings: SettingsStore, storeErrors: StoreErrorReporter
    ) {
        let paster = Paster(
            store: store,
            pasteboard: SystemPasteboard(),
            ax: SystemAccessibility(),
            keys: SystemKeyPoster(),
            apps: SystemAppActivator(),
            sleep: { try? await Task.sleep(for: $0) },
            reportStoreError: { storeErrors.report($0) }
        )
        let actions = HistoryActions(
            paste: { [weak self] id, copyOnly in self?.panel?.paste(id: id, copyOnly: copyOnly) },
            close: { [weak self] in self?.panel?.hide() },
            openSettings: { [weak self] in self?.openSettings() },
            beep: { NSSound.beep() },
            prune: {
                await storeErrors.reportIfStoreError {
                    try await store.prune(limit: settings.historyLimit, maxAgeDays: settings.maxAgeDays, now: Date())
                }
            },
            systemBanners: { [weak self] in self?.systemBanners() ?? [] },
            reportStoreError: { storeErrors.report($0) }
        )
        let model = HistoryViewModel(store: store, actions: actions)
        self.model = model
        panel = PanelController(
            model: model,
            settings: settings,
            paster: paster,
            statusButtonFrame: { [weak self] in self?.statusItem?.buttonScreenFrame },
            restoreFocus: { [weak self] in self?.restoreFocus() }
        )
        model.setLaunchBanners(recovered: result.recoveredFromCorruption, storageUnavailable: result.storageUnavailable)
        for event in bufferedEvents { model.report(event) }
        bufferedEvents = []
        if let placement = gate.markReady() { panel?.show(placement) }
    }

    // MARK: Observers

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let activated = workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let source = SourceApp(bundleID: app?.bundleIdentifier, name: app?.localizedName)
            let handle = app.map(SourceAppHandle.init)
            MainActor.assumeIsolated { self?.appActivated(source, handle: handle) }
        }
        let woke = workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.pruneNow() }
        }
        let distributed = DistributedNotificationCenter.default()
        let show = distributed.addObserver(
            forName: .init(AppIdentity.showNotification), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestOpen(.centred) }
        }
        observers = [(workspace, activated), (workspace, woke), (distributed, show)]
    }

    /// Another app coming forward (⌘Tab, a click elsewhere, a link the panel opened) closes the panel.
    /// Paster activates the target only after the panel has closed, so a paste never lands here first.
    private func appActivated(_ source: SourceApp, handle: SourceAppHandle?) {
        watcher?.appActivated(source)
        if let handle, focus.appActivated(handle) { panel?.hide() }
    }

    /// Gives focus back to the last other app, unless the user is in the Settings window.
    private func restoreFocus() {
        guard settingsWindow?.isVisible != true, let app = focus.lastExternalApp else { return }
        _ = SystemAppActivator().activate(app)
    }

    private func pruneNow() {
        guard let store, let settings, let storeErrors else { return }
        let limit = settings.historyLimit
        let maxAgeDays = settings.maxAgeDays
        Task {
            await storeErrors.reportIfStoreError {
                try await store.prune(limit: limit, maxAgeDays: maxAgeDays, now: Date())
            }
        }
    }

    /// Holds a user-initiated activity while capturing so App Nap doesn't stretch the poll timer.
    private func trackCaptureActivity() {
        guard let settings else { return }
        withObservationTracking {
            if settings.isPaused {
                if let captureActivity { ProcessInfo.processInfo.endActivity(captureActivity) }
                captureActivity = nil
            } else if captureActivity == nil {
                captureActivity = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep, reason: "Clipboard capture"
                )
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackCaptureActivity() }
        }
    }

    // MARK: Panel and settings

    private func requestOpen(_ placement: OpenPlacement, toggle: Bool = false) {
        if toggle, let panel, panel.isVisible {
            panel.hide()
            return
        }
        if let ready = gate.request(placement) { panel?.show(ready) }
    }

    private func systemBanners() -> Set<Banner> {
        var banners: Set<Banner> = []
        if settings?.pasteOnSelect == true, !AXIsProcessTrusted() { banners.insert(.accessibility) }
        if #available(macOS 15.4, *), NSPasteboard.general.accessBehavior == .alwaysDeny {
            banners.insert(.pasteboardDenied)
        }
        if Bundle.main.bundlePath.contains("/AppTranslocation/") { banners.insert(.appTranslocated) }
        return banners
    }

    private func handle(_ event: StoreEvent) {
        if let model {
            model.report(event)
        } else {
            bufferedEvents.append(event)
        }
    }

    /// Main menu target (⌘,).
    @objc func openSettings(_ sender: Any?) {
        openSettings()
    }

    /// Closes the panel first, so focus returns to the target app if Settings is closed.
    func openSettings() {
        panel?.hide()
        guard let settings, let store, let storeErrors else {
            Log.panel.info("settings requested before the store opened")
            return
        }
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: settings, store: store, retention: RetentionChanger(store: store, settings: settings),
                storeErrors: storeErrors,
                onClose: { [weak self] in self?.settingsClosed() }
            )
        }
        settingsWindow?.show()
    }

    /// A windowless accessory app would otherwise stay active with nothing to type into.
    private func settingsClosed() {
        guard panel?.isVisible != true, let app = focus.lastExternalApp else { return }
        _ = SystemAppActivator().activate(app)
    }

    // MARK: Lifecycle

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requestOpen(.centred)
        return false
    }

    /// Commits a pending deletion and any pending scrub before exit. Store work runs on the store
    /// actor, never on the main thread, so waiting here can't deadlock. Errors are classified off the
    /// main thread (no banner any more, but corruption still leaves the repair flag for the next launch).
    func applicationWillTerminate(_ notification: Notification) {
        guard let store else { return }
        let pending = model?.takePendingDeletionForTermination()
        let supportDirectory = openResult?.supportDirectory
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                if let p = pending { _ = try await store.delete(id: p.id, ifLastCopiedAt: p.lastCopiedAt) }
                try await store.scrubIfPending()
            } catch {
                _ = StoreErrorClassifier.classify(error, supportDirectory: supportDirectory)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
        // In-memory fallback only: its image files must not outlive the session.
        openResult?.removeTemporaryBlobs()
    }
}
