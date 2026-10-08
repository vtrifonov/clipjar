import CoreGraphics
import Foundation
import ImageIO

public struct BlobFiles: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func imageName(hash: String, uti: String) -> String {
        uti == "public.png" ? "\(hash).png" : "\(hash).tiff"
    }

    public static func thumbnailName(hash: String) -> String {
        "\(hash).thumb.png"
    }

    public func url(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    public func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    /// Atomic write plus POSIX 0600, only if absent. Returns true iff this call created the file.
    public func writeIfAbsent(_ data: Data, name: String) throws -> Bool {
        let fm = FileManager.default
        if exists(name) { return false }
        try fm.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let target = url(name)
        try data.write(to: target, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return true
    }

    public func read(_ name: String) -> Data? {
        try? Data(contentsOf: url(name))
    }

    /// Missing files are ignored; other errors are logged (domain and code only) and ignored.
    public func remove(_ names: [String]) {
        for name in names where exists(name) {
            do {
                try FileManager.default.removeItem(at: url(name))
            } catch {
                let e = error as NSError
                Log.store.error("blob remove failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            }
        }
    }

    /// PNG thumbnail, longest edge <= maxPixel (never upscaled); nil if undecodable.
    public static func thumbnail(for imageData: Data, maxPixel: Int = 112) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixel, max(w, h)),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
