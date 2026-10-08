import Combine
import Foundation
@testable import ClipjarCore

/// Records scheduled fires; nothing runs until `fireAll()`.
@MainActor final class FakeScheduler {
    struct Entry {
        let date: Date
        let fire: @MainActor () -> Void
        var cancelled: Bool
        var fired = false
    }

    private(set) var entries: [Entry] = []

    /// Not cancelled, not fired.
    var live: [Entry] { entries.filter { !$0.cancelled && !$0.fired } }

    func schedule(_ d: Date, _ f: @escaping @MainActor () -> Void) -> any Cancellable {
        let index = entries.count
        entries.append(Entry(date: d, fire: f, cancelled: false))
        return AnyCancellable { [weak self] in
            MainActor.assumeIsolated { self?.entries[index].cancelled = true }
        }
    }

    /// Fires every non-cancelled, not-yet-fired entry once, in order.
    func fireAll() {
        for index in entries.indices where !entries[index].cancelled && !entries[index].fired {
            entries[index].fired = true
            entries[index].fire()
        }
    }
}
