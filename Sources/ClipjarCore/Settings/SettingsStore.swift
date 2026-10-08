import Combine
import Foundation
import Observation

/// User settings persisted in `UserDefaults`. A timed pause clears itself at `pausedUntil`, including
/// after a relaunch. Launch at login is not stored here.
@MainActor @Observable public final class SettingsStore {
    public static let allowedMaxAgeDays = [0, 1, 7, 30, 90, 365]

    private enum Key {
        static let historyLimit = "historyLimit"
        static let maxAgeDays = "maxAgeDays"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let pasteOnSelect = "pasteOnSelect"
        static let isPaused = "isPaused"
        static let pausedUntil = "pausedUntil"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let scheduler: MainScheduler
    @ObservationIgnored private var pauseTimer: (any Cancellable)?

    public var historyLimit: HistoryLimit {
        didSet { defaults.set(historyLimit.rawValue, forKey: Key.historyLimit) }
    }

    public var maxAgeDays: Int {
        didSet { defaults.set(maxAgeDays, forKey: Key.maxAgeDays) }
    }

    public var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Key.ignoredBundleIDs) }
    }

    public var hasLaunchedBefore: Bool {
        didSet { defaults.set(hasLaunchedBefore, forKey: Key.hasLaunchedBefore) }
    }

    public var pasteOnSelect: Bool {
        didSet { defaults.set(pasteOnSelect, forKey: Key.pasteOnSelect) }
    }

    public private(set) var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Key.isPaused) }
    }

    public private(set) var pausedUntil: Date? {
        didSet {
            if let pausedUntil {
                defaults.set(pausedUntil.timeIntervalSince1970, forKey: Key.pausedUntil)
            } else {
                defaults.removeObject(forKey: Key.pausedUntil)
            }
        }
    }

    public init(
        defaults: UserDefaults,
        clock: @escaping @MainActor () -> Date = Date.init,
        scheduler: @escaping MainScheduler = Schedulers.timer
    ) {
        self.defaults = defaults
        self.clock = clock
        self.scheduler = scheduler
        historyLimit = (defaults.object(forKey: Key.historyLimit) as? Int).flatMap(HistoryLimit.init(rawValue:)) ?? .l1000
        let age = defaults.integer(forKey: Key.maxAgeDays)
        maxAgeDays = Self.allowedMaxAgeDays.contains(age) ? age : 0
        ignoredBundleIDs = defaults.stringArray(forKey: Key.ignoredBundleIDs)
            ?? FilterSettings.defaultIgnoredBundleIDs.sorted()
        hasLaunchedBefore = defaults.bool(forKey: Key.hasLaunchedBefore)
        pasteOnSelect = defaults.object(forKey: Key.pasteOnSelect) as? Bool ?? true
        isPaused = defaults.bool(forKey: Key.isPaused)
        pausedUntil = (defaults.object(forKey: Key.pausedUntil) as? Double).map(Date.init(timeIntervalSince1970:))

        if isPaused, let until = pausedUntil {
            if until <= clock() {
                resume()
            } else {
                armPauseTimer(until)
            }
        }
    }

    /// nil = indefinite. Replaces any earlier pause.
    public func pause(for duration: TimeInterval?) {
        pauseTimer?.cancel()
        pauseTimer = nil
        isPaused = true
        pausedUntil = duration.map { clock().addingTimeInterval($0) }
        if let pausedUntil { armPauseTimer(pausedUntil) }
    }

    public func resume() {
        pauseTimer?.cancel()
        pauseTimer = nil
        isPaused = false
        pausedUntil = nil
    }

    public var filterSettings: FilterSettings {
        FilterSettings(ignoredBundleIDs: Set(ignoredBundleIDs), pausedUntil: pausedUntil, isPaused: isPaused)
    }

    private func armPauseTimer(_ date: Date) {
        pauseTimer = scheduler(date) { [weak self] in self?.resume() }
    }
}
