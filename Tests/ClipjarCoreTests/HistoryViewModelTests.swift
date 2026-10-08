import CoreGraphics
import Foundation
import Testing
@testable import ClipjarCore

@MainActor @Suite struct HistoryViewModelTests {
    private func index(_ h: VMHarness) -> Int? {
        h.vm.rows.firstIndex { $0.id == h.vm.selectedID }
    }

    @Test func initialSelectionIsFirstRow() async throws {
        let h = try await VMHarness(count: 3)
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
    }

    @Test func emptyStoreHasNoSelection() async throws {
        let h = try await VMHarness([])
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.vm.selectedID == nil)
        #expect(h.vm.isEmptyHistory)
        #expect(!h.vm.isNoResults)
    }

    @Test func moveBoundsNoWrap() async throws {
        let h = try await VMHarness(count: 3)
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        #expect(h.vm.handle(.moveUp))
        #expect(h.vm.selectedID == h.ids[0])
        for _ in 0..<5 { #expect(h.vm.handle(.moveDown)) }
        #expect(h.vm.selectedID == h.ids[2])
    }

    @Test func moveToTopAndBottom() async throws {
        let h = try await VMHarness(count: 5)
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        #expect(h.vm.handle(.moveToBottom))
        #expect(h.vm.selectedID == h.ids[4])
        #expect(h.vm.handle(.moveToTop))
        #expect(h.vm.selectedID == h.ids[0])
    }

    @Test func pageDownBy8Clamped() async throws {
        let h = try await VMHarness(count: 20)
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        h.vm.handle(.pageDown)
        #expect(index(h) == 8)
        h.vm.handle(.pageDown)
        #expect(index(h) == 16)
        h.vm.handle(.pageDown)
        #expect(index(h) == 19)
        h.vm.handle(.pageUp)
        #expect(index(h) == 11)
    }

    @Test func keyboardMoveSetsScrollTarget() async throws {
        let h = try await VMHarness(count: 3)
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        h.vm.handle(.moveDown)
        #expect(h.vm.scrollTarget == h.vm.selectedID)
        #expect(h.vm.scrollTarget == h.ids[1])
    }

    @Test func activatePastesSelection() async throws {
        let h = try await VMHarness(count: 3)
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        #expect(h.vm.handle(.activate(copyOnly: false)))
        #expect(h.vm.handle(.activate(copyOnly: true)))
        #expect(h.rec.pastes.map(\.0) == [h.ids[0], h.ids[0]])
        #expect(h.rec.pastes.map(\.1) == [false, true])
    }

    @Test func activateWithoutSelectionBeeps() async throws {
        let h = try await VMHarness([])
        #expect(h.vm.handle(.activate(copyOnly: false)) == false)
        #expect(h.rec.beeps == 1)
        #expect(h.rec.pastes.isEmpty)
    }

    @Test func activateRowMapsToIndex() async throws {
        let h = try await VMHarness(count: 3)
        #expect(h.vm.handle(.activateRow(2)))
        #expect(h.rec.pastes.map(\.0) == [h.vm.rows[1].id])
        #expect(h.vm.handle(.activateRow(9)))
        #expect(h.rec.beeps == 1)
        #expect(h.rec.pastes.count == 1)
    }

    @Test func filterCycleWraps() async throws {
        let h = try await VMHarness(count: 1)
        var seen: [FilterChip] = []
        for _ in 0..<6 {
            #expect(h.vm.handle(.nextFilter))
            seen.append(h.vm.filter)
        }
        #expect(seen == [.text, .links, .images, .files, .pinned, .all])
        #expect(h.vm.handle(.previousFilter))
        #expect(h.vm.filter == .pinned)
    }

    @Test func filterChangeSelectsFirst() async throws {
        let h = try await VMHarness([
            Clip.make("https://example.com/docs", kind: .link, at: t0),
            Clip.make("Item 1", at: t0 + 1),
            Clip.make("Item 2", at: t0 + 2),
        ])
        h.vm.select(id: h.ids[2])
        h.vm.filter = .links
        #expect(await eventually { h.vm.rows.map(\.id) == [h.ids[2]] && h.vm.selectedID == h.ids[2] })
        h.vm.select(id: h.ids[2])
        h.vm.filter = .text
        #expect(await eventually { h.vm.rows.count == 2 && h.vm.selectedID == h.ids[0] })
    }

    /// The selected row still matches, so keeping it or the same-index fallback would both leave it selected.
    @Test func filterChangeSelectsFirstEvenWhenSelectionStillMatches() async throws {
        let h = try await VMHarness([
            Clip.make("https://example.com/docs", kind: .link, at: t0),
            Clip.make("Item 1", at: t0 + 1),
            Clip.make("Item 2", at: t0 + 2),
        ])
        h.vm.select(id: h.ids[1])
        h.vm.filter = .text
        #expect(await eventually { h.vm.rows.count == 2 && h.vm.selectedID == h.ids[0] })
    }

    @Test func queryChangeSelectsFirstEvenWhenSelectionStillMatches() async throws {
        let h = try await VMHarness(count: 3)
        h.vm.select(id: h.ids[1])
        h.vm.query = "Item"
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        #expect(h.vm.rows.map(\.id) == h.ids)
    }

    @Test func querySearchesAndHighlights() async throws {
        let h = try await VMHarness([
            Clip.make("Hello, Clipjar", at: t0), Clip.make("Item 1", at: t0 + 1), Clip.make("Item 2", at: t0 + 2),
        ])
        h.vm.query = "clipjar"
        #expect(await eventually { h.vm.rows.map(\.id) == [h.ids[2]] })
        #expect(h.vm.highlightTerms == ["clipjar"])
        #expect(await eventually { h.vm.selectedID == h.ids[2] })
    }

    @Test func escapeClearsQueryThenCloses() async throws {
        let h = try await VMHarness(count: 1)
        h.vm.query = "x"
        #expect(h.vm.handle(.escape))
        #expect(h.vm.query == "")
        #expect(h.rec.closes == 0)
        #expect(h.vm.handle(.escape))
        #expect(h.rec.closes == 1)
    }

    @Test func selectionKeptOnDbUpdate() async throws {
        let h = try await VMHarness(count: 3)
        h.vm.select(id: h.ids[1])
        try await h.fx.store.ingest(text("Brand new"), source: nil, at: t0 + 100)
        #expect(await eventually { h.vm.rows.count == 4 })
        #expect(h.vm.selectedID == h.ids[1])
    }

    @Test func selectionFallsBackToSameIndex() async throws {
        let h = try await VMHarness(count: 3)
        h.vm.select(id: h.ids[1])
        try await h.fx.store.delete(id: h.ids[1])
        #expect(await eventually { h.vm.rows.count == 2 })
        #expect(h.vm.selectedID == h.ids[2])
        #expect(index(h) == 1)
    }

    @Test func pagingTrigger() async throws {
        let h = try await VMHarness(count: 250)
        #expect(h.vm.rows.count == 100)
        h.vm.rowAppeared(index: 10)
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.vm.rows.count == 100)
        h.vm.rowAppeared(index: 85)
        #expect(await eventually { h.vm.rows.count == 200 })
    }

    @Test func hoverNeedsMouseMovement() async throws {
        let h = try await VMHarness(count: 3)
        let p = CGPoint(x: 10, y: 10)
        h.vm.hover(id: h.ids[1], mouseLocation: p)
        #expect(h.vm.selectedID == h.ids[1])
        h.vm.hover(id: h.ids[2], mouseLocation: p)
        #expect(h.vm.selectedID == h.ids[1])
        h.vm.hover(id: h.ids[2], mouseLocation: CGPoint(x: 10, y: 30))
        #expect(h.vm.selectedID == h.ids[2])
        #expect(h.vm.scrollTarget == nil)
    }

    @Test func hoverIgnoredRightAfterKeyMove() async throws {
        let h = try await VMHarness(count: 3)
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        h.vm.handle(.moveDown)
        h.clock.now = t0 + 0.1
        h.vm.hover(id: h.ids[2], mouseLocation: CGPoint(x: 1, y: 1))
        #expect(h.vm.selectedID == h.ids[1])
        h.clock.now = t0 + 0.2
        h.vm.hover(id: h.ids[2], mouseLocation: CGPoint(x: 1, y: 5))
        #expect(h.vm.selectedID == h.ids[2])
    }

    @Test func togglePinPersists() async throws {
        let h = try await VMHarness(count: 2)
        #expect(await eventually { h.vm.selectedID == h.ids[0] })
        #expect(h.vm.handle(.togglePin))
        let store = h.fx.store
        let id = h.ids[0]
        var pinned = false
        for _ in 0..<200 where !pinned {
            pinned = try await store.clip(id: id)?.isPinned == true
            if !pinned { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(pinned)
        #expect(await eventually { h.vm.selectedClip?.isPinned == true })
    }

    @Test func selectedClipFollowsSelection() async throws {
        let h = try await VMHarness(count: 3)
        #expect(await eventually { h.vm.selectedClip?.id == h.ids[0] })
        h.vm.handle(.moveDown)
        #expect(await eventually { h.vm.selectedClip?.id == h.vm.selectedID && h.vm.selectedID == h.ids[1] })
    }

    @Test func matchAndAllCounts() async throws {
        let h = try await VMHarness([
            Clip.make("Hello, Clipjar", at: t0), Clip.make("Item 1", at: t0 + 1), Clip.make("Item 2", at: t0 + 2),
        ])
        h.vm.query = "clipjar"
        #expect(await eventually { h.vm.matchCount == 1 && h.vm.allCount == 3 })
    }

    @Test func selectAndActivateById() async throws {
        let h = try await VMHarness(count: 3)
        h.vm.select(id: h.ids[2])
        #expect(h.vm.selectedID == h.ids[2])
        h.vm.activate(id: h.ids[1], copyOnly: true)
        #expect(h.vm.selectedID == h.ids[1])
        #expect(h.rec.pastes.map(\.0) == [h.ids[1]])
        #expect(h.rec.pastes.map(\.1) == [true])
    }

    @Test func openSettingsAndClose() async throws {
        let h = try await VMHarness(count: 1)
        #expect(h.vm.handle(.openSettings))
        #expect(h.vm.handle(.close))
        #expect(h.rec.settingsOpens == 1)
        #expect(h.rec.closes == 1)
    }
}
