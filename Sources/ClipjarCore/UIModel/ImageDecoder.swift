import CoreGraphics
import Foundation
import ImageIO

/// Off-main image decoding; call from a detached task.
public enum ImageDecoder {
    /// Decodes a thumbnail no larger than `maxPixelSize` on its longest side (never upscaled),
    /// applying the image's orientation. nil when the file is missing or undecodable.
    public static func decode(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
