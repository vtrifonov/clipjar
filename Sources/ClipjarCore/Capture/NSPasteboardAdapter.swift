import AppKit

/// `NSPasteboard` adapter. Every write carries `PasteboardTypes.marker` so the watcher skips Clipjar's own writes.
@MainActor public final class SystemPasteboard: PasteboardReading, PasteboardWriting {
    private let pb: NSPasteboard

    public init(_ pb: NSPasteboard = .general) {
        self.pb = pb
    }

    public var changeCount: Int { pb.changeCount }

    public func types() -> Set<String> {
        Set(pb.pasteboardItems?.flatMap(\.types).map(\.rawValue) ?? [])
    }

    public func declaredSource() -> String? {
        pb.string(forType: .init(PasteboardTypes.source))
    }

    public func fileURLs() -> [URL] {
        pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    public func string() -> String? {
        pb.string(forType: .string)
    }

    public func data(forType type: String) -> Data? {
        pb.data(forType: .init(type))
    }

    public func write(_ payload: ClipPayload) {
        pb.clearContents()
        let marker = NSPasteboard.PasteboardType(PasteboardTypes.marker)
        switch payload {
        case let .text(plain, rtf, html):
            let item = NSPasteboardItem()
            item.setString(plain, forType: .string)
            if let rtf { item.setData(rtf, forType: .rtf) }
            if let html { item.setData(html, forType: .html) }
            item.setData(Data(), forType: marker)
            pb.writeObjects([item])
        case let .image(image):
            let item = NSPasteboardItem()
            item.setData(image.data, forType: .init(image.uti))
            item.setData(Data(), forType: marker)
            pb.writeObjects([item])
        case let .files(urls):
            pb.writeObjects(urls as [NSURL])
            pb.pasteboardItems?.first?.setData(Data(), forType: marker)
        }
    }
}
