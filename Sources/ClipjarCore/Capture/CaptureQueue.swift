import Foundation
import os

public struct CaptureItem: Sendable {
    public var content: CapturedContent
    public var source: SourceApp?
    public var at: Date

    public init(content: CapturedContent, source: SourceApp?, at: Date) {
        self.content = content
        self.source = source
        self.at = at
    }
}

/// Unbounded buffer between the watcher and the store, so captures made before the store opens
/// are kept and every capture is ingested in copy order.
public final class CaptureQueue: Sendable {
    private let stream: AsyncStream<CaptureItem>
    private let continuation: AsyncStream<CaptureItem>.Continuation
    private let started = OSAllocatedUnfairLock(initialState: false)

    public init() {
        (stream, continuation) = AsyncStream.makeStream(of: CaptureItem.self, bufferingPolicy: .unbounded)
    }

    public func yield(_ item: CaptureItem) {
        continuation.yield(item)
    }

    public func finish() {
        continuation.finish()
    }

    /// Single long-lived consumer; call once. Ingests sequentially in yield order; an ingest error
    /// is reported through `onEvent` and never stops the loop. Later calls are logged and return a
    /// task that does nothing, since an AsyncStream supports only one iterator.
    public func startConsuming(
        store: ClipStore,
        supportDirectory: URL?,
        onEvent: @escaping @MainActor @Sendable (StoreEvent) -> Void
    ) -> Task<Void, Never> {
        let alreadyStarted = started.withLock { started in
            defer { started = true }
            return started
        }
        guard !alreadyStarted else {
            Log.store.fault("capture queue consumer started twice")
            return Task {}
        }
        let stream = stream
        return Task {
            for await item in stream {
                do {
                    _ = try await store.ingest(item.content, source: item.source, at: item.at)
                } catch {
                    let event = StoreErrorClassifier.classify(error, supportDirectory: supportDirectory)
                    Log.store.error("capture ingest failed: \(String(describing: event), privacy: .public)")
                    await onEvent(event)
                }
            }
        }
    }
}
