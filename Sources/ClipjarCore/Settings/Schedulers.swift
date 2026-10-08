import Combine
import Foundation

/// Schedules a one-shot fire at a date; cancelling the result prevents it.
public typealias MainScheduler = @MainActor (Date, @escaping @MainActor () -> Void) -> any Cancellable

public enum Schedulers {
    /// Production: one-shot Timer on RunLoop.main in .common mode.
    @MainActor public static func timer(_ date: Date, _ fire: @escaping @MainActor () -> Void) -> any Cancellable {
        let box = FireBox(fire)
        let t = Timer(fire: date, interval: 0, repeats: false) { _ in MainActor.assumeIsolated { box.fire() } }
        RunLoop.main.add(t, forMode: .common)
        return AnyCancellable { t.invalidate() }
    }
}

/// Carries a MainActor closure into the Timer's Sendable block.
@MainActor private final class FireBox {
    let fire: @MainActor () -> Void

    init(_ fire: @escaping @MainActor () -> Void) {
        self.fire = fire
    }
}
