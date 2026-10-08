import Foundation
import Testing
@testable import ClipjarCore

@MainActor @Suite struct HistoryViewModelDeleteTests {
    /// Polls the store until the clip's presence matches `exists`.
    private func storeEventually(_ h: VMHarness, _ id: Int64, exists: Bool) async throws -> Bool {
        for _ in 0..<200 {
            if try await (h.fx.store.clip(id: id) != nil) == exists { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func ready(_ count: Int) async throws -> VMHarness {
        let h = try await VMHarness(count: count)
        #expect(await eventually { h.vm.selectedID == h.ids.first })
        return h
    }

    @Test func deleteHidesRowAndShowsToast() async throws {
        let h = try await ready(3)
        h.vm.select(id: h.ids[1])
        #expect(h.vm.handle(.delete))
        #expect(!h.vm.rows.contains { $0.id == h.ids[1] })
        #expect(h.vm.toast == .deleted(h.ids[1]))
        #expect(h.vm.selectedID == h.ids[2])
        #expect(try await h.fx.store.clip(id: h.ids[1]) != nil)
    }

    @Test func undoRestoresRowAndSelection() async throws {
        let h = try await ready(3)
        h.vm.select(id: h.ids[1])
        h.vm.handle(.delete)
        #expect(h.vm.handle(.undoDelete))
        #expect(h.vm.rows.map(\.id) == h.ids)
        #expect(h.vm.selectedID == h.ids[1])
        #expect(h.vm.toast == nil)
        #expect(h.scheduler.live.isEmpty)
        #expect(try await h.fx.store.clip(id: h.ids[1]) != nil)
    }

    @Test func undoWithoutToastNotConsumed() async throws {
        let h = try await ready(3)
        #expect(h.vm.handle(.undoDelete) == false)
    }

    @Test func commitOnToastExpiry() async throws {
        let h = try await ready(3)
        h.vm.handle(.delete)
        #expect(h.scheduler.live.first?.date == t0 + 5)
        h.scheduler.fireAll()
        #expect(try await storeEventually(h, h.ids[0], exists: false))
        #expect(h.vm.toast == nil)
        #expect(await eventually { h.vm.rows.count == 2 })
    }

    @Test func commitOnPanelClose() async throws {
        let h = try await ready(3)
        h.vm.handle(.delete)
        await h.vm.commitPendingDeletion()?.value
        #expect(try await h.fx.store.clip(id: h.ids[0]) == nil)
        #expect(h.vm.commitPendingDeletion() == nil)
    }

    @Test func commitOnNextDelete() async throws {
        let h = try await ready(3)
        h.vm.handle(.delete)
        #expect(h.vm.selectedID == h.ids[1])
        h.vm.handle(.delete)
        #expect(try await storeEventually(h, h.ids[0], exists: false))
        #expect(try await h.fx.store.clip(id: h.ids[1]) != nil)
        #expect(h.vm.toast == .deleted(h.ids[1]))
        #expect(h.vm.rows.map(\.id) == [h.ids[2]])
    }

    @Test func escapeWithToastCommitsAndKeepsPanel() async throws {
        let h = try await ready(3)
        h.vm.handle(.delete)
        #expect(h.vm.handle(.escape))
        #expect(h.vm.toast == nil)
        #expect(try await storeEventually(h, h.ids[0], exists: false))
        #expect(h.rec.closes == 0)
    }

    @Test func recopiedDuringUndoWindowSurvives() async throws {
        let h = try await ready(3)
        let a = h.ids[2]
        h.vm.select(id: a)
        h.vm.handle(.delete)
        try await h.fx.store.ingest(text("Item 0"), source: nil, at: t0 + 100)
        h.scheduler.fireAll()
        #expect(await eventually { h.vm.rows.contains { $0.id == a } })
        #expect(try await h.fx.store.clip(id: a) != nil)
    }

    @Test func recopyDuringUndoWindowShowsRowImmediately() async throws {
        let h = try await ready(3)
        let a = h.ids[2]
        h.vm.select(id: a)
        h.vm.handle(.delete)
        try await h.fx.store.ingest(text("Item 0"), source: nil, at: t0 + 100)
        #expect(await eventually { h.vm.rows.first?.id == a })
        #expect(h.vm.toast == nil)
        #expect(h.scheduler.live.isEmpty)
        #expect(h.vm.handle(.undoDelete) == false)
        #expect(try await h.fx.store.clip(id: a) != nil)
    }

    @Test func matchCountExcludesPendingRow() async throws {
        let h = try await ready(3)
        #expect(await eventually { h.vm.matchCount == 3 })
        h.vm.handle(.delete)
        #expect(h.vm.matchCount == 2)
        h.vm.handle(.undoDelete)
        #expect(h.vm.matchCount == 3)
        h.vm.handle(.delete)
        await h.vm.commitPendingDeletion()?.value
        #expect(await eventually { h.vm.matchCount == 2 && h.vm.rows.count == 2 })
    }

    @Test func commitErrorReportsAndRestoresRow() async throws {
        let h = try await ready(3)
        try await h.fx.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER no_delete BEFORE DELETE ON clip BEGIN SELECT RAISE(ABORT, 'x'); END")
        }
        h.vm.handle(.delete)
        #expect(h.vm.rows.count == 2)
        await h.vm.commitPendingDeletion()?.value
        #expect(h.rec.storeErrors == 1)
        #expect(h.vm.rows.map(\.id) == h.ids)
        #expect(try await h.fx.store.clip(id: h.ids[0]) != nil)
    }

    @Test func firstPinnedDeleteCommitsPendingDeletion() async throws {
        let h = try await VMHarness([Clip.make("Item 0", at: t0), Clip.make("Pinned", at: t0 + 1, pinned: true)])
        let (pinned, item) = (h.ids[0], h.ids[1])
        #expect(await eventually { h.vm.selectedID == pinned })
        h.vm.select(id: item)
        h.vm.handle(.delete)
        #expect(h.vm.toast == .deleted(item))
        #expect(h.vm.selectedID == pinned)
        #expect(h.vm.handle(.delete))
        #expect(h.vm.toast == .confirmPinnedDelete(pinned))
        #expect(h.vm.handle(.undoDelete) == false)
        #expect(try await storeEventually(h, item, exists: false))
        #expect(h.vm.rows.map(\.id) == [pinned])
    }

    @Test func deletingLastRowSelectsNewLast() async throws {
        let h = try await ready(3)
        h.vm.select(id: h.ids[2])
        h.vm.handle(.delete)
        #expect(h.vm.selectedID == h.ids[1])
    }

    @Test func pagingContinuesWhilePending() async throws {
        let h = try await ready(101)
        #expect(h.vm.rows.count == 100)
        h.vm.handle(.delete)
        #expect(h.vm.rows.count == 99)
        h.vm.rowAppeared(index: 98)
        #expect(await eventually { h.vm.rows.count == 100 })
    }

    @Test func pinnedNeedsSecondDelete() async throws {
        let h = try await VMHarness([Clip.make("Item 0", at: t0), Clip.make("Pinned", at: t0 + 1, pinned: true)])
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        let id = h.ids[0]
        #expect(h.vm.handle(.delete))
        #expect(h.vm.toast == .confirmPinnedDelete(id))
        #expect(h.vm.rows.contains { $0.id == id })
        h.clock.now = t0 + 1
        #expect(h.vm.handle(.delete))
        #expect(h.vm.toast == .deleted(id))
        #expect(!h.vm.rows.contains { $0.id == id })
    }

    @Test func pinnedConfirmationExpires() async throws {
        let h = try await VMHarness([Clip.make("Item 0", at: t0), Clip.make("Pinned", at: t0 + 1, pinned: true)])
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        let id = h.ids[0]
        h.vm.handle(.delete)
        h.clock.now = t0 + 3
        h.vm.handle(.delete)
        #expect(h.vm.toast == .confirmPinnedDelete(id))
        #expect(h.vm.rows.contains { $0.id == id })
    }

    @Test func pinnedConfirmationToastClears() async throws {
        let h = try await VMHarness([Clip.make("Pinned", at: t0, pinned: true)])
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        h.vm.handle(.delete)
        #expect(h.scheduler.live.first?.date == t0 + 2)
        h.scheduler.fireAll()
        #expect(h.vm.toast == nil)
    }

    @Test func terminationTakeClearsPending() async throws {
        let h = try await ready(3)
        h.vm.handle(.delete)
        let taken = h.vm.takePendingDeletionForTermination()
        #expect(taken == PendingDeletion(id: h.ids[0], lastCopiedAt: t0 + 2, index: 0))
        #expect(h.vm.takePendingDeletionForTermination() == nil)
        #expect(h.vm.toast == nil)
        #expect(h.scheduler.live.isEmpty)
    }

    @Test func deleteWithoutSelectionBeeps() async throws {
        let h = try await VMHarness([])
        #expect(h.vm.handle(.delete))
        #expect(h.rec.beeps == 1)
        #expect(h.vm.toast == nil)
    }

    @Test func dismissToastCommits() async throws {
        let h = try await ready(3)
        h.vm.handle(.delete)
        h.vm.dismissToast()
        #expect(h.vm.toast == nil)
        #expect(try await storeEventually(h, h.ids[0], exists: false))
    }
}
