import AppKit
import ClipjarCore

/// Decoded thumbnails/previews (decoded off the main thread) and app icons, both kept in memory.
@MainActor final class ImageCache {
    static let shared = ImageCache()

    private let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    private let icons = NSCache<NSString, NSImage>()
    /// Bundle ids with no installed app, so the lookup isn't repeated for every row.
    private var missingIcons: Set<String> = []

    static func key(_ url: URL, maxPixelSize: Int) -> String {
        "\(url.path)#\(maxPixelSize)"
    }

    func cachedImage(_ key: String) -> NSImage? {
        images.object(forKey: key as NSString)
    }

    /// nil when the file is missing or undecodable. The image's size is its pixel size.
    func image(at url: URL, maxPixelSize: Int) async -> NSImage? {
        let key = Self.key(url, maxPixelSize: maxPixelSize)
        if let cached = cachedImage(key) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            ImageDecoder.decode(url: url, maxPixelSize: maxPixelSize)
        }.value
        guard let decoded, !Task.isCancelled else { return nil }
        let image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        images.setObject(image, forKey: key as NSString)
        return image
    }

    func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID, !missingIcons.contains(bundleID) else { return nil }
        if let cached = icons.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missingIcons.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }
}
