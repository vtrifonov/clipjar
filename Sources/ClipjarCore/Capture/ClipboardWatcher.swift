import Foundation

/// Polls the pasteboard and hands accepted clips to `sink`. Any app that could have produced a copy
/// (declared source, frontmost at the last tick, apps activated since, frontmost now) is checked
/// against the ignore list before any content is read.
@MainActor public final class ClipboardWatcher {
    private let pasteboard: PasteboardReading
    private let settings: @MainActor () -> FilterSettings
    private let frontmostApp: @MainActor () -> SourceApp?
    private let runningAppName: @MainActor (String) -> String?
    private let ownBundleID: String
    private let clock: @MainActor () -> Date
    private let sink: @MainActor (CapturedContent, SourceApp?, Date) -> Void

    /// nil until the first poll, so the clipboard present at launch is captured.
    private var lastChangeCount: Int?
    private var frontmostAtLastTick: SourceApp?
    private var activatedSinceTick: [SourceApp] = []
    private var task: Task<Void, Never>?

    public var onCapture: (@MainActor () -> Void)?

    public init(
        pasteboard: PasteboardReading,
        settings: @escaping @MainActor () -> FilterSettings,
        frontmostApp: @escaping @MainActor () -> SourceApp?,
        runningAppName: @escaping @MainActor (String) -> String? = { _ in nil },
        ownBundleID: String,
        clock: @escaping @MainActor () -> Date = Date.init,
        sink: @escaping @MainActor (CapturedContent, SourceApp?, Date) -> Void
    ) {
        self.pasteboard = pasteboard
        self.settings = settings
        self.frontmostApp = frontmostApp
        self.runningAppName = runningAppName
        self.ownBundleID = ownBundleID
        self.clock = clock
        self.sink = sink
    }

    deinit {
        task?.cancel()
    }

    /// Polls immediately, then every `interval`.
    public func start(interval: Duration = .milliseconds(300)) {
        task?.cancel()
        // Activations seen while stopped are stale.
        activatedSinceTick = []
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: interval, tolerance: .milliseconds(100))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        activatedSinceTick = []
    }

    public func appActivated(_ app: SourceApp) {
        activatedSinceTick.append(app)
    }

    public func poll() {
        // Tick state resets on every tick, including no-change ticks.
        let frontNow = frontmostApp()
        let prevFront = frontmostAtLastTick
        let activated = activatedSinceTick
        frontmostAtLastTick = frontNow
        activatedSinceTick = []

        // Advance before filtering: content copied while paused or ignored is never captured later.
        let cc = pasteboard.changeCount
        if cc == lastChangeCount { return }
        lastChangeCount = cc

        let types = pasteboard.types()
        let declaredApp = pasteboard.declaredSource().map { SourceApp(bundleID: $0, name: runningAppName($0)) }
        let candidates = ([declaredApp, prevFront] + activated + [frontNow]).compactMap { $0 }
        let current = settings()
        let decision = ClipFilter.preflight(
            types: types, candidates: candidates, settings: current, ownBundleID: ownBundleID, now: clock()
        )
        if case let .reject(reason) = decision {
            Log.capture.info("capture skipped: \(String(describing: reason), privacy: .public)")
            return
        }

        let snapshot: PasteboardSnapshot
        switch ClipReader.read(pasteboard, types: types, limits: current) {
        case let .snapshot(s): snapshot = s
        case .oversized:
            Log.capture.info("capture skipped: oversized")
            return
        case .empty:
            Log.capture.info("capture skipped: empty")
            return
        }
        // A newer copy may have replaced the preflighted one during the read; drop what was read
        // so the next tick preflights the new copy.
        guard pasteboard.changeCount == cc else {
            Log.capture.info("capture skipped: changed during read")
            return
        }
        guard let content = ClipExtractor.extract(snapshot) else { return }

        // A declared source counts only when an app with that bundle id is running.
        let declared = declaredApp?.name != nil ? declaredApp : nil
        let source = Self.attributedSource(declared: declared, frontmost: frontNow, ownBundleID: ownBundleID)
        sink(content, source, clock())
        onCapture?()
    }

    public nonisolated static func attributedSource(
        declared: SourceApp?, frontmost: SourceApp?, ownBundleID: String
    ) -> SourceApp? {
        guard let app = declared ?? frontmost, app.bundleID != ownBundleID else { return nil }
        return app
    }
}
