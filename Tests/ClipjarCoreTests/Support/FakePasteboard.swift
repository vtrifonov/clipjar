import Foundation
@testable import ClipjarCore

/// In-memory pasteboard that counts content reads. `types()` and `declaredSource()` are metadata and not counted.
@MainActor final class FakePasteboard: PasteboardReading, PasteboardWriting {
    var changeCount = 0
    var typeSet: Set<String> = []
    var declared: String?
    var urls: [URL] = []
    var stringValue: String?
    var dataByType: [String: Data] = [:]
    /// fileURLs → "public.file-url", string → "public.utf8-plain-text", data(t) → t
    private(set) var reads: [String: Int] = [:]
    var totalDataReads: Int { reads.values.reduce(0, +) }
    private(set) var written: [ClipPayload] = []
    var onWrite: (() -> Void)?

    /// Replaces the contents and bumps `changeCount`; does not reset `reads`.
    func copy(
        types: Set<String>, string: String? = nil, urls: [URL] = [], data: [String: Data] = [:], declared: String? = nil
    ) {
        typeSet = types
        stringValue = string
        self.urls = urls
        dataByType = data
        self.declared = declared
        changeCount += 1
    }

    func resetReads() {
        reads = [:]
    }

    func types() -> Set<String> { typeSet }

    func declaredSource() -> String? { declared }

    func fileURLs() -> [URL] {
        reads[PasteboardTypes.fileURL, default: 0] += 1
        return urls
    }

    func string() -> String? {
        reads[PasteboardTypes.string, default: 0] += 1
        return stringValue
    }

    func data(forType type: String) -> Data? {
        reads[type, default: 0] += 1
        return dataByType[type]
    }

    func write(_ payload: ClipPayload) {
        written.append(payload)
        changeCount += 1
        onWrite?()
    }
}
