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
    private var model: HistoryViewModel?
    private var panel: PanelController?
    private var settingsWindow: SettingsWindowController?
    /// Open requests made before the panel exists; replayed once it does.
    private var gate = OpenGate()
    /// Store events reported before the view model exists.
    private var bufferedEvents: [StoreEvent] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var captureActivity: NSObjectProtocol?

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
            await store.configure(limit: settings.historyLimit, maxAgeDays: settings.maxAgeDays)
            _ = try? await store.prune(limit: settings.historyLimit, maxAgeDays: settings.maxAgeDays, now: Date())
            _ = captures.startConsuming(store: store, supportDirectory: result.supportDirectory) {
                self.handle($0)
            }
            Task.detached(priority: .utility) { _ = try? await store.cleanOrphanBlobs(now: Date()) }

            buildPanel(store: store, result: result, settings: settings)
        }

        // 8. First launch shows the panel once, centred.
        if !settings.hasLaunchedBefore {
            settings.hasLaunchedBefore = true
            requestOpen(.centred)
        }
    }

    private func buildPanel(store: ClipStore, result: OpenResult, settings: SettingsStore) {
        let paster = Paster(
            store: store,
            pasteboard: SystemPasteboard(),
            ax: SystemAccessibility(),
            keys: SystemKeyPoster(),
            apps: SystemAppActivator(),
            sleep: { try? await Task.sleep(for: $0) }
        )
        let supportDirectory = result.supportDirectory
        let actions = HistoryActions(
            paste: { [weak self] id, copyOnly in self?.panel?.paste(id: id, copyOnly: copyOnly) },
            close: { [weak self] in self?.panel?.hide() },
            openSettings: { [weak self] in self?.openSettings() },
            beep: { NSSound.beep() },
            prune: {
                _ = try? await store.prune(limit: settings.historyLimit, maxAgeDays: settings.maxAgeDays, now: Date())
            },
            systemBanners: { [weak self] in self?.systemBanners() ?? [] },
            reportStoreError: { [weak self] error in
                self?.handle(StoreErrorClassifier.classify(error, supportDirectory: supportDirectory))
            }
        )
        let model = HistoryViewModel(store: store, actions: actions)
        self.model = model
        panel = PanelController(
            model: model,
            settings: settings,
            paster: paster,
            statusButtonFrame: { [weak self] in self?.statusItem?.buttonScreenFrame }
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
            MainActor.assumeIsolated { self?.watcher?.appActivated(source) }
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

    private func pruneNow() {
        guard let store, let settings else { return }
        let limit = settings.historyLimit
        let maxAgeDays = settings.maxAgeDays
        Task { _ = try? await store.prune(limit: limit, maxAgeDays: maxAgeDays, now: Date()) }
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
        guard let settings, let store else {
            Log.panel.info("settings requested before the store opened")
            return
        }
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: settings, store: store, retention: RetentionChanger(store: store, settings: settings)
            )
        }
        settingsWindow?.show()
    }

    // MARK: Lifecycle

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requestOpen(.centred)
        return false
    }

    /// Commits a pending deletion and any pending scrub before exit. Store work runs on the store
    /// actor, never on the main thread, so waiting here can't deadlock.
    func applicationWillTerminate(_ notification: Notification) {
        guard let store else { return }
        let pending = model?.takePendingDeletionForTermination()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            if let p = pending { _ = try? await store.delete(id: p.id, ifLastCopiedAt: p.lastCopiedAt) }
            try? await store.scrubIfPending()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }
}
