import Combine
import CoreGraphics
import Foundation
import GRDB
import Observation

/// State and commands for the history panel. Rows, counts and the selected clip come from store
/// observations; changing the query, filter or page limit restarts them.
@MainActor @Observable public final class HistoryViewModel {
    public static let pageSize = 100
    private static let pageJump = 8
    private static let pagingThreshold = 15
    /// Hover is ignored this soon after a keyboard move, so a row scrolling under a still pointer can't steal the selection.
    private static let hoverQuietPeriod: TimeInterval = 0.150

    public let store: ClipStore

    public var query: String = "" {
        didSet { if query != oldValue { queryOrFilterChanged() } }
    }

    public var filter: FilterChip = .all {
        didSet { if filter != oldValue { queryOrFilterChanged() } }
    }

    /// Fetched rows minus the pending deletion.
    public private(set) var rows: [ClipRow] = []
    public private(set) var selectedID: Int64?
    public private(set) var selectedClip: Clip?
    /// Matching clips, not counting rows hidden as deleted.
    public private(set) var matchCount = 0
    public private(set) var allCount = 0
    public private(set) var banners: [Banner] = []
    public private(set) var toast: Toast?
    public private(set) var highlightTerms: [String] = []
    /// Set by keyboard moves and on every open; the view scrolls whenever it changes.
    public private(set) var scrollRequest: ScrollRequest?
    /// +1 per `prepareForOpen`; the view refocuses the search field when it changes.
    public private(set) var openGeneration = 0
    /// True from an open until its first rows arrive, so the panel doesn't flash "no results".
    private var awaitingOpenRows = false

    /// The row of the latest scroll request.
    public var scrollTarget: Int64? { scrollRequest?.id }
    public var isEmptyHistory: Bool { allCount == 0 }
    public var isNoResults: Bool { rows.isEmpty && !isEmptyHistory && !awaitingOpenRows }

    /// Internal test hook, called with every fetched rows emission.
    @ObservationIgnored var onRowsEmitted: (([ClipRow]) -> Void)?

    @ObservationIgnored private let actions: HistoryActions
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let scheduler: MainScheduler
    @ObservationIgnored private var limit = pageSize
    /// Rows as fetched, before hiding the pending deletion; paging compares its count with `limit`.
    @ObservationIgnored private var fetchedRows: [ClipRow] = []
    @ObservationIgnored private var selectFirstOnNextRows = true
    /// Index of the selection when last seen, used when the selected row disappears.
    @ObservationIgnored private var selectedIndex: Int?
    @ObservationIgnored private var lastKeyMoveAt: Date?
    @ObservationIgnored private var lastMouseLocation: CGPoint?
    @ObservationIgnored private var rowsTask: Task<Void, Never>?
    @ObservationIgnored private var matchTask: Task<Void, Never>?
    @ObservationIgnored private var allTask: Task<Void, Never>?
    @ObservationIgnored private var clipTask: Task<Void, Never>?

    /// The undoable deletion behind the `.deleted` toast; at most one at a time.
    @ObservationIgnored private var pending: PendingDeletion?
    @ObservationIgnored private var pendingExpiry: (any Cancellable)?
    /// Deletions being committed, then deleted rows until an emission no longer contains them.
    @ObservationIgnored private var committingIDs: Set<Int64> = []
    @ObservationIgnored private var deletedIDs: Set<Int64> = []
    /// First ⌘⌫ on a pinned clip; a second one on the same clip within the window deletes it.
    @ObservationIgnored private var pinnedConfirmation: (id: Int64, at: Date)?
    @ObservationIgnored private var pinnedConfirmationExpiry: (any Cancellable)?
    private static let undoWindow: TimeInterval = 5
    private static let pinnedConfirmationWindow: TimeInterval = 2

    @ObservationIgnored private var systemBanners: Set<Banner> = []
    @ObservationIgnored private var launchBanners: Set<Banner> = []
    @ObservationIgnored private var runtimeBanners: Set<Banner> = []
    @ObservationIgnored private var storageErrorExpiry: (any Cancellable)?
    private static let storageErrorDuration: TimeInterval = 6
    /// Set from `prepareForOpen` until its prune finishes: rows stay empty and query/filter changes only
    /// record state, so the observations restarted after the prune use the latest query.
    @ObservationIgnored private var isPreparingOpen = false
    @ObservationIgnored private var scrollToFirstOnNextRows = false
    @ObservationIgnored private var scrollSerial = 0
    /// Count from the store; `matchCount` subtracts the hidden rows.
    @ObservationIgnored private var fetchedMatchCount = 0
    /// After an open the first hover only records the pointer, which may have moved while the panel was hidden.
    @ObservationIgnored private var hoverNeedsBaseline = false

    public init(
        store: ClipStore,
        actions: HistoryActions,
        clock: @escaping @MainActor () -> Date = Date.init,
        scheduler: @escaping MainScheduler = Schedulers.timer
    ) {
        self.store = store
        self.actions = actions
        self.clock = clock
        self.scheduler = scheduler
        startObservations(selectFirst: true)
        allTask = observe(store.countObservation(.all)) { [weak self] in self?.allCount = $0 }
    }

    deinit {
        rowsTask?.cancel()
        matchTask?.cancel()
        allTask?.cancel()
        clipTask?.cancel()
    }

    // MARK: Commands

    /// True when the command was consumed.
    @discardableResult
    public func handle(_ cmd: PanelCommand) -> Bool {
        switch cmd {
        case .moveUp: moveSelection(to: (currentIndex ?? 0) - 1)
        case .moveDown: moveSelection(to: (currentIndex ?? -1) + 1)
        case .moveToTop: moveSelection(to: 0)
        case .moveToBottom: moveSelection(to: rows.count - 1)
        case .pageUp: moveSelection(to: (currentIndex ?? 0) - Self.pageJump)
        case .pageDown: moveSelection(to: (currentIndex ?? 0) + Self.pageJump)
        case let .activate(copyOnly):
            guard let id = selectedID else {
                actions.beep()
                return false
            }
            actions.paste(id, copyOnly)
        case let .activateRow(n):
            guard rows.indices.contains(n - 1) else {
                actions.beep()
                return true
            }
            activate(id: rows[n - 1].id, copyOnly: false)
        case .togglePin:
            guard let id = selectedID, let row = rows.first(where: { $0.id == id }) else { return false }
            let store = store
            let report = actions.reportStoreError
            Task {
                do {
                    try await store.setPinned(id: id, !row.isPinned)
                } catch {
                    report(error)
                }
            }
        case .nextFilter: cycleFilter(by: 1)
        case .previousFilter: cycleFilter(by: -1)
        case .escape:
            if toast != nil {
                dismissToast()
            } else if query.isEmpty {
                actions.close()
            } else {
                query = ""
            }
        case .close: actions.close()
        case .openSettings: actions.openSettings()
        case .delete: deleteSelection()
        case .undoDelete: return undoDelete()
        }
        return true
    }

    // MARK: Open and banners

    /// Resets the panel for a new open. Rows and selection clear at once and observations restart only
    /// after the open-time prune, so this open never shows or pastes a clip the prune removes.
    @discardableResult
    public func prepareForOpen() -> Task<Void, Never> {
        rowsTask?.cancel()
        matchTask?.cancel()
        isPreparingOpen = true
        awaitingOpenRows = true
        query = ""
        filter = .all
        limit = Self.pageSize
        fetchedRows = []
        selectFirstOnNextRows = true
        applyRows()
        hoverNeedsBaseline = true
        openGeneration += 1
        let generation = openGeneration
        systemBanners = actions.systemBanners()
        updateBanners()
        let prune = actions.prune
        return Task { [weak self] in
            await prune()
            // A later open owns the restart once its own prune finishes.
            guard let self, openGeneration == generation else { return }
            isPreparingOpen = false
            scrollToFirstOnNextRows = true
            startObservations(selectFirst: true)
        }
    }

    public func setLaunchBanners(recovered: Bool, storageUnavailable: Bool) {
        if recovered { launchBanners.insert(.recoveredFromCorruption) }
        if storageUnavailable { launchBanners.insert(.storageUnavailable) }
        updateBanners()
    }

    /// `.writeFailed` shows a storage error that hides itself; `.corrupt` stays until dismissed.
    public func report(_ event: StoreEvent) {
        switch event {
        case .writeFailed:
            runtimeBanners.insert(.storageError)
            storageErrorExpiry?.cancel()
            storageErrorExpiry = scheduler(clock().addingTimeInterval(Self.storageErrorDuration)) { [weak self] in
                self?.removeRuntimeBanner(.storageError)
            }
        case .corrupt:
            runtimeBanners.insert(.storageCorrupt)
        }
        updateBanners()
    }

    /// Only dismissible banners can be removed; launch banners never come back once dismissed.
    public func dismiss(_ banner: Banner) {
        guard banner.isDismissible else { return }
        launchBanners.remove(banner)
        removeRuntimeBanner(banner)
    }

    private func removeRuntimeBanner(_ banner: Banner) {
        if banner == .storageError {
            storageErrorExpiry?.cancel()
            storageErrorExpiry = nil
        }
        runtimeBanners.remove(banner)
        updateBanners()
    }

    private func updateBanners() {
        let active = systemBanners.union(launchBanners).union(runtimeBanners)
        banners = Banner.allCases.filter(active.contains)
    }

    // MARK: Delete / undo

    /// Commits the pending deletion: `DELETE … WHERE id AND lastCopiedAt`, so a clip re-copied during the
    /// undo window survives and reappears. nil when nothing is pending.
    @discardableResult
    public func commitPendingDeletion() -> Task<Void, Never>? {
        cancelPendingExpiry()
        guard let p = pending else { return nil }
        pending = nil
        if case .deleted = toast { toast = nil }
        committingIDs.insert(p.id)
        let store = store
        return Task { [weak self] in
            var deleted = false
            do {
                deleted = try await store.delete(id: p.id, ifLastCopiedAt: p.lastCopiedAt)
            } catch {
                self?.actions.reportStoreError(error)
            }
            self?.finishCommit(p.id, deleted: deleted)
        }
    }

    /// For app termination: hands the pending deletion to the caller, which commits it.
    public func takePendingDeletionForTermination() -> PendingDeletion? {
        cancelPendingExpiry()
        guard let p = pending else { return nil }
        pending = nil
        deletedIDs.insert(p.id)
        if case .deleted = toast { toast = nil }
        return p
    }

    /// Dismissing the delete toast commits the deletion.
    public func dismissToast() {
        switch toast {
        case .deleted: commitPendingDeletion()
        case .confirmPinnedDelete: clearPinnedConfirmation()
        case nil: break
        }
    }

    private func deleteSelection() {
        guard let index = currentIndex else {
            actions.beep()
            return
        }
        let row = rows[index]
        if row.isPinned, !confirmsPinnedDelete(of: row.id) {
            commitPendingDeletion()
            pinnedConfirmation = (row.id, clock())
            toast = .confirmPinnedDelete(row.id)
            pinnedConfirmationExpiry?.cancel()
            pinnedConfirmationExpiry = scheduler(clock().addingTimeInterval(Self.pinnedConfirmationWindow)) {
                [weak self] in
                if self?.toast == .confirmPinnedDelete(row.id) { self?.clearPinnedConfirmation() }
            }
            return
        }
        clearPinnedConfirmation()
        commitPendingDeletion()
        pending = PendingDeletion(id: row.id, lastCopiedAt: row.lastCopiedAt, index: index)
        applyRows()
        toast = .deleted(row.id)
        pendingExpiry = scheduler(clock().addingTimeInterval(Self.undoWindow)) { [weak self] in
            self?.commitPendingDeletion()
        }
    }

    private func confirmsPinnedDelete(of id: Int64) -> Bool {
        guard let c = pinnedConfirmation, c.id == id else { return false }
        return clock().timeIntervalSince(c.at) <= Self.pinnedConfirmationWindow
    }

    private func clearPinnedConfirmation() {
        pinnedConfirmationExpiry?.cancel()
        pinnedConfirmationExpiry = nil
        pinnedConfirmation = nil
        if case .confirmPinnedDelete = toast { toast = nil }
    }

    private func undoDelete() -> Bool {
        guard case let .deleted(id) = toast, let p = pending, p.id == id else { return false }
        cancelPendingExpiry()
        pending = nil
        toast = nil
        applyRows()
        select(id: id)
        return true
    }

    private func finishCommit(_ id: Int64, deleted: Bool) {
        committingIDs.remove(id)
        if deleted && fetchedRows.contains(where: { $0.id == id }) { deletedIDs.insert(id) }
        applyRows()
    }

    private func cancelPendingExpiry() {
        pendingExpiry?.cancel()
        pendingExpiry = nil
    }

    /// Selects the hovered row only when the pointer really moved and no keyboard move just happened.
    public func hover(id: Int64, mouseLocation: CGPoint) {
        let moved = !hoverNeedsBaseline && lastMouseLocation != mouseLocation
        hoverNeedsBaseline = false
        lastMouseLocation = mouseLocation
        guard moved else { return }
        if let last = lastKeyMoveAt, clock().timeIntervalSince(last) < Self.hoverQuietPeriod { return }
        select(id: id)
    }

    /// Loads the next page when a row near the end appears and the current page was full.
    public func rowAppeared(index: Int) {
        guard !isPreparingOpen, index >= rows.count - Self.pagingThreshold, fetchedRows.count == limit else { return }
        limit += Self.pageSize
        startObservations(selectFirst: false)
    }

    public func select(id: Int64) {
        setSelection(id, index: rows.firstIndex { $0.id == id })
    }

    public func activate(id: Int64, copyOnly: Bool) {
        select(id: id)
        actions.paste(id, copyOnly)
    }

    // MARK: Observation

    private func queryOrFilterChanged() {
        guard !isPreparingOpen else { return }
        limit = Self.pageSize
        startObservations(selectFirst: true)
    }

    private func startObservations(selectFirst: Bool) {
        rowsTask?.cancel()
        matchTask?.cancel()
        let parsed = QueryParser.parse(query)
        let q = QueryParser.clipQuery(parsed, chip: filter, limit: limit)
        highlightTerms = parsed.terms
        if selectFirst { selectFirstOnNextRows = true }
        rowsTask = observe(store.rowsObservation(q)) { [weak self] in self?.receive($0) }
        matchTask = observe(store.countObservation(q)) { [weak self] in
            self?.fetchedMatchCount = $0
            self?.updateMatchCount()
        }
    }

    private func observe<T>(
        _ observation: ValueObservation<ValueReducers.Fetch<T>>, _ onValue: @escaping @MainActor (T) -> Void
    ) -> Task<Void, Never> {
        let reader = store.reader
        return Task { [weak self] in
            do {
                for try await value in observation.values(in: reader) {
                    guard !Task.isCancelled else { return }
                    onValue(value)
                }
            } catch is CancellationError {
            } catch {
                self?.actions.reportStoreError(error)
            }
        }
    }

    private func receive(_ fetched: [ClipRow]) {
        fetchedRows = fetched
        // A deleted row stays hidden only until an emission without it arrives.
        deletedIDs.formIntersection(fetched.map(\.id))
        dropPendingIfRecopied(fetched)
        onRowsEmitted?(fetched)
        awaitingOpenRows = false
        applyRows()
        if scrollToFirstOnNextRows {
            scrollToFirstOnNextRows = false
            requestScroll(to: rows.first?.id)
        }
    }

    /// A clip re-copied during the undo window is no longer pending: its row shows again at once.
    private func dropPendingIfRecopied(_ fetched: [ClipRow]) {
        guard let p = pending, let row = fetched.first(where: { $0.id == p.id }), row.lastCopiedAt != p.lastCopiedAt
        else { return }
        cancelPendingExpiry()
        pending = nil
        if case .deleted = toast { toast = nil }
    }

    /// Selection rules: first row after a query/filter change (once rows exist); otherwise keep the
    /// selected row, else the row now at its previous index, else nothing.
    private func applyRows() {
        rows = fetchedRows.filter { row in
            row.id != pending?.id && !committingIDs.contains(row.id) && !deletedIDs.contains(row.id)
        }
        updateMatchCount()
        if selectFirstOnNextRows {
            if let first = rows.first {
                selectFirstOnNextRows = false
                setSelection(first.id, index: 0)
            } else {
                setSelection(nil, index: nil)
            }
            return
        }
        if let id = selectedID, let i = rows.firstIndex(where: { $0.id == id }) {
            selectedIndex = i
            return
        }
        if let i = selectedIndex, !rows.isEmpty {
            let clamped = min(i, rows.count - 1)
            setSelection(rows[clamped].id, index: clamped)
        } else {
            setSelection(nil, index: nil)
        }
    }

    /// Rows hidden as deleted are still in the store's count until their deletion commits.
    private func updateMatchCount() {
        let count = max(0, fetchedMatchCount - (fetchedRows.count - rows.count))
        if count != matchCount { matchCount = count }
    }

    private func setSelection(_ id: Int64?, index: Int?) {
        selectedIndex = index
        guard id != selectedID else { return }
        selectedID = id
        clipTask?.cancel()
        selectedClip = nil
        if let id {
            clipTask = observe(store.clipObservation(id: id)) { [weak self] in self?.selectedClip = $0 }
        }
    }

    // MARK: Helpers

    private var currentIndex: Int? {
        selectedID.flatMap { id in rows.firstIndex { $0.id == id } }
    }

    private func moveSelection(to index: Int) {
        guard !rows.isEmpty else { return }
        let clamped = min(max(index, 0), rows.count - 1)
        setSelection(rows[clamped].id, index: clamped)
        requestScroll(to: selectedID)
        lastKeyMoveAt = clock()
    }

    private func requestScroll(to id: Int64?) {
        guard let id else { return }
        scrollSerial += 1
        scrollRequest = ScrollRequest(id: id, serial: scrollSerial)
    }

    private func cycleFilter(by step: Int) {
        let all = FilterChip.allCases
        let i = all.firstIndex(of: filter) ?? 0
        filter = all[(i + step + all.count) % all.count]
    }
}
