import Foundation

public enum RetentionDecision: Equatable, Sendable { case applied, needsConfirmation(removing: Int) }

/// Applies history limit / age changes, asking for confirmation first when they would remove clips.
@MainActor public struct RetentionChanger {
    private let store: ClipStore
    private let settings: SettingsStore
    private let clock: @MainActor () -> Date

    public init(store: ClipStore, settings: SettingsStore, clock: @escaping @MainActor () -> Date = Date.init) {
        self.store = store
        self.settings = settings
        self.clock = clock
    }

    /// Applies the change when it removes nothing; otherwise changes nothing and reports how many clips it would remove.
    public func propose(limit: HistoryLimit, maxAgeDays: Int) async throws -> RetentionDecision {
        let removing = try await store.pruneCount(limit: limit, maxAgeDays: maxAgeDays, now: clock())
        guard removing > 0 else {
            try await apply(limit: limit, maxAgeDays: maxAgeDays)
            return .applied
        }
        return .needsConfirmation(removing: removing)
    }

    /// Persists the settings, configures the store and prunes now.
    public func apply(limit: HistoryLimit, maxAgeDays: Int) async throws {
        settings.historyLimit = limit
        settings.maxAgeDays = maxAgeDays
        await store.configure(limit: limit, maxAgeDays: maxAgeDays)
        try await store.prune(limit: limit, maxAgeDays: maxAgeDays, now: clock())
    }
}
