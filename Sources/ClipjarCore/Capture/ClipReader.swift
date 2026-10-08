import Foundation

public enum ReadResult: Sendable, Equatable { case snapshot(PasteboardSnapshot), oversized, empty }

/// Second phase of capture: reads only the representation that will become the clip
/// (files, else text plus rich reps, else PNG, else TIFF), within the size limits.
@MainActor public enum ClipReader {
    public static func read(_ pb: PasteboardReading, types: Set<String>, limits: FilterSettings) -> ReadResult {
        var snapshot = PasteboardSnapshot(changeCount: pb.changeCount, types: types, declaredSource: pb.declaredSource())

        if types.contains(PasteboardTypes.fileURL) {
            let urls = pb.fileURLs()
            if !urls.isEmpty {
                snapshot.fileURLs = urls
                return .snapshot(snapshot)
            }
        }

        if types.contains(PasteboardTypes.string), let s = pb.string(), s.contains(where: { !$0.isWhitespace }) {
            if s.utf8.count > limits.maxTextBytes { return .oversized }
            snapshot.string = s
            snapshot.rtf = richData(pb, types: types, type: PasteboardTypes.rtf)
            snapshot.html = richData(pb, types: types, type: PasteboardTypes.html)
            return .snapshot(snapshot)
        }

        // TIFF is never read when PNG is declared: it can be many times larger.
        let imageType = types.contains(PasteboardTypes.png) ? PasteboardTypes.png
            : types.contains(PasteboardTypes.tiff) ? PasteboardTypes.tiff : nil
        if let imageType, let data = pb.data(forType: imageType) {
            if data.count > limits.maxImageBytes { return .oversized }
            snapshot.image = ImageData(data: data, uti: imageType)
            return .snapshot(snapshot)
        }

        return .empty
    }

    private static func richData(_ pb: PasteboardReading, types: Set<String>, type: String) -> Data? {
        guard types.contains(type), let data = pb.data(forType: type), data.count <= FilterSettings.maxRichBytes
        else { return nil }
        return data
    }
}
