import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@MainActor @Suite struct RetentionChangerTests {
    private let defaults = UserDefaults(suiteName: "clipjar-tests-\(UUID().uuidString)")!
    private let fx: StoreFixture
    private let settings: SettingsStore
    private let changer: RetentionChanger

    init() throws {
        fx = try makeStore(.memoryQueue)
        let scheduler = FakeScheduler()
        settings = SettingsStore(defaults: defaults, clock: { t0 }, scheduler: { scheduler.schedule($0, $1) })
        changer = RetentionChanger(store: fx.store, settings: settings, clock: { t0 })
    }

    private func items(_ count: Int, prefix: String, at date: Date = t0 - 1000, pinned: Bool = false) -> [Clip] {
        (0..<count).map { Clip.make("\(prefix) \($0)", at: date + Double($0), pinned: pinned) }
    }

    @Test func zeroRemovalAppliesImmediately() async throws {
        try seed(fx.writer, items(10, prefix: "Item"))
        #expect(try await changer.propose(limit: .l200, maxAgeDays: 0) == .applied)
        #expect(settings.historyLimit == .l200)
        try seed(fx.writer, items(200, prefix: "More"))
        try await fx.store.ingest(text("New item"), source: nil, at: t0)
        #expect(try clipCount(fx.writer) == 200)
    }

    @Test func positiveRemovalNeedsConfirmation() async throws {
        try seed(fx.writer, items(205, prefix: "Item") + items(2, prefix: "Pinned", at: t0 - 5000, pinned: true))
        #expect(try await changer.propose(limit: .l200, maxAgeDays: 0) == .needsConfirmation(removing: 5))
        #expect(settings.historyLimit == .l1000)
        #expect(try clipCount(fx.writer) == 207)
    }

    @Test func applyPrunesAndKeepsPins() async throws {
        try seed(fx.writer, items(205, prefix: "Item") + items(2, prefix: "Pinned", at: t0 - 5000, pinned: true))
        try await changer.apply(limit: .l200, maxAgeDays: 0)
        #expect(try clipCount(fx.writer) == 202)
        let pinned = try await fx.writer.read { try Clip.filter(Column("isPinned") == true).fetchCount($0) }
        #expect(pinned == 2)
        #expect(settings.historyLimit == .l200)
        #expect(defaults.integer(forKey: "historyLimit") == 200)
    }

    @Test func ageChangeCounts() async throws {
        try seed(fx.writer, items(3, prefix: "Old", at: t0 - 40 * 86_400) + items(2, prefix: "Recent"))
        #expect(try await changer.propose(limit: .l1000, maxAgeDays: 30) == .needsConfirmation(removing: 3))
        #expect(settings.maxAgeDays == 0)
    }
}
