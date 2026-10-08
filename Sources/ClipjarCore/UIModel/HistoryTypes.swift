import Foundation

/// Panel banners, in display order.
public enum Banner: Equatable, Sendable, Hashable, CaseIterable {
    case accessibility, pasteboardDenied, appTranslocated, recoveredFromCorruption, storageUnavailable, storageError,
         storageCorrupt

    /// System banners reflect current state and cannot be dismissed.
    public var isDismissible: Bool {
        switch self {
        case .recoveredFromCorruption, .storageUnavailable, .storageError, .storageCorrupt: true
        case .accessibility, .pasteboardDenied, .appTranslocated: false
        }
    }
}

public enum Toast: Equatable, Sendable { case deleted(Int64), confirmPinnedDelete(Int64) }

public struct PendingDeletion: Sendable, Equatable {
    public let id: Int64
    public let lastCopiedAt: Date
    public let index: Int

    public init(id: Int64, lastCopiedAt: Date, index: Int) {
        self.id = id
        self.lastCopiedAt = lastCopiedAt
        self.index = index
    }
}

/// Effects the view model asks the app to perform.
@MainActor public struct HistoryActions {
    /// (id, copyOnly)
    public var paste: @MainActor (Int64, Bool) -> Void
    public var close: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void
    public var beep: @MainActor () -> Void
    /// Open-time prune with the current settings.
    public var prune: @MainActor () async -> Void
    /// accessibility / pasteboardDenied / appTranslocated, evaluated on every open.
    public var systemBanners: @MainActor () -> Set<Banner>
    public var reportStoreError: @MainActor (any Error) -> Void

    public init(
        paste: @escaping @MainActor (Int64, Bool) -> Void = { _, _ in },
        close: @escaping @MainActor () -> Void = {},
        openSettings: @escaping @MainActor () -> Void = {},
        beep: @escaping @MainActor () -> Void = {},
        prune: @escaping @MainActor () async -> Void = {},
        systemBanners: @escaping @MainActor () -> Set<Banner> = { [] },
        reportStoreError: @escaping @MainActor (any Error) -> Void = { _ in }
    ) {
        self.paste = paste
        self.close = close
        self.openSettings = openSettings
        self.beep = beep
        self.prune = prune
        self.systemBanners = systemBanners
        self.reportStoreError = reportStoreError
    }
}
