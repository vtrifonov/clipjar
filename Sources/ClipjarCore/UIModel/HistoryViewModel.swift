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
    public private(set) var matchCount = 0
    public private(set) var allCount = 0
    public private(set) var banners: [Banner] = []
    public private(set) var toast: Toast?
    public private(set) var highlightTerms: [String] = []
    /// Set only by keyboard moves; the view scrolls to it.
    public private(set) var scrollTarget: Int64?
    /// +1 per `prepareForOpen`; the view refocuses the search field when it changes.
    public private(set) var openGeneration = 0

    public var isEmptyHistory: Bool { allCount == 0 }
    public var isNoResults: Bool { rows.isEmpty && !isEmptyHistory }

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
            if query.isEmpty {
                actions.close()
            } else {
                query = ""
            }
        case .close: actions.close()
        case .openSettings: actions.openSettings()
        case .delete, .undoDelete: return false
        }
        return true
    }

    /// Selects the hovered row only when the pointer really moved and no keyboard move just happened.
    public func hover(id: Int64, mouseLocation: CGPoint) {
        let moved = lastMouseLocation != mouseLocation
        lastMouseLocation = mouseLocation
        guard moved else { return }
        if let last = lastKeyMoveAt, clock().timeIntervalSince(last) < Self.hoverQuietPeriod { return }
        select(id: id)
    }

    /// Loads the next page when a row near the end appears and the current page was full.
    public func rowAppeared(index: Int) {
        guard index >= rows.count - Self.pagingThreshold, fetchedRows.count == limit else { return }
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
        matchTask = observe(store.countObservation(q)) { [weak self] in self?.matchCount = $0 }
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
        onRowsEmitted?(fetched)
        applyRows()
    }

    /// Selection rules: first row after a query/filter change (once rows exist); otherwise keep the
    /// selected row, else the row now at its previous index, else nothing.
    private func applyRows() {
        rows = fetchedRows
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
        scrollTarget = selectedID
        lastKeyMoveAt = clock()
    }

    private func cycleFilter(by step: Int) {
        let all = FilterChip.allCases
        let i = all.firstIndex(of: filter) ?? 0
        filter = all[(i + step + all.count) % all.count]
    }
}
