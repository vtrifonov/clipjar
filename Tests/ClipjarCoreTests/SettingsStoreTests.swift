import AppKit
import Foundation
import Observation
import os
import Testing
@testable import ClipjarCore

@MainActor @Suite struct SettingsStoreTests {
    private let tempDefaults = TempDefaults()
    private var defaults: UserDefaults { tempDefaults.defaults }
    private let scheduler = FakeScheduler()

    private func makeSettings(now: Date = t0) -> SettingsStore {
        let scheduler = scheduler
        return SettingsStore(defaults: defaults, clock: { now }, scheduler: { scheduler.schedule($0, $1) })
    }

    private func makeSettings(clock: TestClock, center: NotificationCenter) -> SettingsStore {
        let scheduler = scheduler
        return SettingsStore(
            defaults: defaults, clock: { clock.now }, scheduler: { scheduler.schedule($0, $1) },
            wakeNotifications: center
        )
    }

    /// The run-loop timer doesn't advance during sleep, so wake re-checks the pause against the clock.
    @Test func wakeAfterPauseExpiryResumes() async {
        let clock = TestClock()
        let center = NotificationCenter()
        let s = makeSettings(clock: clock, center: center)
        s.pause(for: 900)
        clock.now = t0 + 3600
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(await eventually { !s.isPaused })
        #expect(s.pausedUntil == nil)
        #expect(scheduler.live.isEmpty)
    }

    @Test func wakeBeforePauseExpiryRearms() async {
        let clock = TestClock()
        let center = NotificationCenter()
        let s = makeSettings(clock: clock, center: center)
        s.pause(for: 900)
        clock.now = t0 + 600
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(await eventually { scheduler.entries.count == 2 })
        #expect(s.isPaused)
        #expect(scheduler.live.count == 1)
        #expect(scheduler.live.first?.date == t0 + 900)
    }

    @Test func wakeWithIndefinitePauseKeepsPause() async throws {
        let clock = TestClock()
        let center = NotificationCenter()
        let s = makeSettings(clock: clock, center: center)
        s.pause(for: nil)
        clock.now = t0 + 99_999
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(s.isPaused)
        #expect(scheduler.entries.isEmpty)
    }

    @Test func defaultValues() {
        let s = makeSettings()
        #expect(s.historyLimit == .l1000)
        #expect(s.maxAgeDays == 0)
        #expect(s.ignoredBundleIDs == FilterSettings.defaultIgnoredBundleIDs.sorted())
        #expect(s.ignoredBundleIDs.count == 4)
        #expect(!s.hasLaunchedBefore)
        #expect(!s.isPaused)
        #expect(s.pausedUntil == nil)
        #expect(s.pasteOnSelect)
    }

    @Test func roundTrip() {
        let s = makeSettings()
        s.historyLimit = .l5000
        s.maxAgeDays = 30
        s.ignoredBundleIDs = ["com.example.editor"]
        s.hasLaunchedBefore = true
        s.pasteOnSelect = false
        s.pause(for: 900)
        let reread = makeSettings()
        #expect(reread.historyLimit == .l5000)
        #expect(reread.maxAgeDays == 30)
        #expect(reread.ignoredBundleIDs == ["com.example.editor"])
        #expect(reread.hasLaunchedBefore)
        #expect(!reread.pasteOnSelect)
        #expect(reread.isPaused)
        #expect(reread.pausedUntil == t0.addingTimeInterval(900))
    }

    @Test func invalidStoredValuesFallBack() {
        defaults.set(123, forKey: "historyLimit")
        defaults.set(5, forKey: "maxAgeDays")
        let s = makeSettings()
        #expect(s.historyLimit == .l1000)
        #expect(s.maxAgeDays == 0)
    }

    @Test func timedPauseFires() {
        let s = makeSettings()
        s.pause(for: 900)
        #expect(scheduler.live.first?.date == t0.addingTimeInterval(900))
        #expect(s.filterSettings.isPaused)
        #expect(s.filterSettings.pausedUntil == t0.addingTimeInterval(900))
        scheduler.fireAll()
        #expect(!s.isPaused)
        #expect(s.pausedUntil == nil)
        #expect(defaults.bool(forKey: "isPaused") == false)
        #expect(defaults.object(forKey: "pausedUntil") == nil)
    }

    @Test func observersNotifiedOnFire() {
        let s = makeSettings()
        s.pause(for: 900)
        let flag = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking({ _ = s.isPaused }, onChange: { flag.withLock { $0 = true } })
        scheduler.fireAll()
        #expect(flag.withLock { $0 })
    }

    @Test func rearmedOnInit() {
        defaults.set(true, forKey: "isPaused")
        defaults.set(t0.addingTimeInterval(600).timeIntervalSince1970, forKey: "pausedUntil")
        let s = makeSettings()
        #expect(s.isPaused)
        #expect(scheduler.live.count == 1)
        #expect(scheduler.live.first?.date == t0.addingTimeInterval(600))
    }

    @Test func expiredPauseClearedOnInit() {
        defaults.set(true, forKey: "isPaused")
        defaults.set(t0.addingTimeInterval(-1).timeIntervalSince1970, forKey: "pausedUntil")
        let s = makeSettings()
        #expect(!s.isPaused)
        #expect(s.pausedUntil == nil)
        #expect(scheduler.entries.isEmpty)
        #expect(defaults.bool(forKey: "isPaused") == false)
    }

    @Test func resumeCancelsTimer() {
        let s = makeSettings()
        s.pause(for: 900)
        s.resume()
        #expect(scheduler.live.isEmpty)
        #expect(!s.isPaused)
        #expect(s.pausedUntil == nil)
    }

    @Test func newPauseReplacesOld() {
        let s = makeSettings()
        s.pause(for: 900)
        s.pause(for: 60)
        #expect(scheduler.live.count == 1)
        #expect(scheduler.live.first?.date == t0.addingTimeInterval(60))
    }

    @Test func indefinitePause() {
        let s = makeSettings()
        s.pause(for: nil)
        #expect(s.isPaused)
        #expect(s.pausedUntil == nil)
        #expect(scheduler.entries.isEmpty)
        let reread = makeSettings()
        #expect(reread.isPaused)
        #expect(reread.pausedUntil == nil)
        #expect(scheduler.entries.isEmpty)
    }

    @Test func filterSettingsSnapshot() {
        let s = makeSettings()
        s.ignoredBundleIDs = ["com.example.editor", "com.example.vault"]
        #expect(s.filterSettings.ignoredBundleIDs == Set(s.ignoredBundleIDs))
        #expect(!s.filterSettings.isPaused)
    }
}
