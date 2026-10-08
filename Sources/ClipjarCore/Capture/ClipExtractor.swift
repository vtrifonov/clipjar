import Foundation
import ImageIO

/// Classifies a snapshot into a clip: files, else text/link, else image. Pure.
public enum ClipExtractor {
    public static func extract(_ s: PasteboardSnapshot) -> CapturedContent? {
        let files = s.fileURLs.filter(\.isFileURL)
        if !files.isEmpty {
            return CapturedContent(kind: .file, plainText: files.map(\.path).joined(separator: "\n"), fileURLs: files)
        }

        if let string = s.string, string.contains(where: { !$0.isWhitespace }) {
            return CapturedContent(
                kind: TextHeuristics.isLink(string) ? .link : .text,
                plainText: string,
                rtf: s.rtf.flatMap(withinRichLimit),
                html: s.html.flatMap(withinRichLimit)
            )
        }

        if let image = s.image, let size = pixelSize(image.data) {
            return CapturedContent(kind: .image, plainText: "", image: image, width: size.width, height: size.height)
        }

        return nil
    }

    private static func withinRichLimit(_ data: Data) -> Data? {
        data.count <= FilterSettings.maxRichBytes ? data : nil
    }

    private static func pixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
