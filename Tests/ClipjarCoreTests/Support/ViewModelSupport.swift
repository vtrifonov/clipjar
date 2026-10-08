import Foundation
@testable import ClipjarCore

@MainActor final class ActionRecorder {
    var pastes: [(Int64, Bool)] = []
    var closes = 0
    var settingsOpens = 0
    var beeps = 0
    var storeErrors = 0
    var systemBanners: Set<Banner> = []
    var pruneHook: (@MainActor () async -> Void)?

    func actions() -> HistoryActions {
        HistoryActions(
            paste: { [unowned self] id, copyOnly in pastes.append((id, copyOnly)) },
            close: { [unowned self] in closes += 1 },
            openSettings: { [unowned self] in settingsOpens += 1 },
            beep: { [unowned self] in beeps += 1 },
            prune: { [unowned self] in await pruneHook?() },
            systemBanners: { [unowned self] in systemBanners },
            reportStoreError: { [unowned self] _ in storeErrors += 1 }
        )
    }
}

/// Controllable clock for view-model tests.
@MainActor final class TestClock {
    var now = t0
}

/// A view model over a `.memoryQueue` store seeded with `clips`; waits for the first rows.
@MainActor final class VMHarness {
    let fx: StoreFixture
    let rec = ActionRecorder()
    let clock = TestClock()
    let scheduler = FakeScheduler()
    let vm: HistoryViewModel
    /// Seeded ids, newest first (the display order when seeded at increasing times).
    let ids: [Int64]

    init(_ clips: [Clip]) async throws {
        fx = try makeStore(.memoryQueue)
        ids = try seed(fx.writer, clips).reversed()
        let clock = clock
        let scheduler = scheduler
        vm = HistoryViewModel(
            store: fx.store, actions: rec.actions(), clock: { clock.now },
            scheduler: { scheduler.schedule($0, $1) }
        )
        let expected = min(clips.count, HistoryViewModel.pageSize)
        let vm = vm
        _ = await eventually { vm.rows.count == expected && vm.allCount == clips.count }
    }

    convenience init(count: Int) async throws {
        try await self.init((0..<count).map { Clip.make("Item \($0)", at: t0 + Double($0)) })
    }
}

/// Polls every 10 ms until `cond` holds or `timeout` passes.
@MainActor func eventually(timeout: Duration = .seconds(2), _ cond: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if cond() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return cond()
}
