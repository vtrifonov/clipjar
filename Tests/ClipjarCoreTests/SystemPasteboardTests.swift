import AppKit
import Testing
@testable import ClipjarCore

/// Every test uses its own uniquely named pasteboard; never the general (user) pasteboard.
@MainActor @Suite struct SystemPasteboardTests {
    private func withPasteboard(_ body: (NSPasteboard, SystemPasteboard) throws -> Void) rethrows {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        try body(pb, SystemPasteboard(pb))
    }

    @Test func writeTextIncludesMarkerAndRichReps() {
        withPasteboard { _, adapter in
            let rtf = Data("{\\rtf1 Hello, Clipjar}".utf8)
            let html = Data("<b>Hello, Clipjar</b>".utf8)
            adapter.write(.text(plain: "Hello, Clipjar", rtf: rtf, html: html))
            #expect(adapter.types().isSuperset(of: [
                PasteboardTypes.marker, PasteboardTypes.string, PasteboardTypes.rtf, PasteboardTypes.html,
            ]))
            #expect(adapter.string() == "Hello, Clipjar")
            #expect(adapter.data(forType: PasteboardTypes.rtf) == rtf)
            #expect(adapter.data(forType: PasteboardTypes.html) == html)
        }
    }

    @Test func writePlainTextOmitsRichReps() {
        withPasteboard { _, adapter in
            adapter.write(.text(plain: "Hello, Clipjar", rtf: nil, html: nil))
            let types = adapter.types()
            #expect(types.contains(PasteboardTypes.marker))
            #expect(!types.contains(PasteboardTypes.rtf))
            #expect(!types.contains(PasteboardTypes.html))
        }
    }

    @Test func writeImage() {
        withPasteboard { _, adapter in
            let png = TestImages.png(width: 4, height: 4)
            adapter.write(.image(ImageData(data: png, uti: PasteboardTypes.png)))
            #expect(adapter.data(forType: PasteboardTypes.png) == png)
            #expect(adapter.types().contains(PasteboardTypes.marker))
        }
    }

    @Test func writeFilesRoundTrip() throws {
        let dir = try TempDir()
        let urls = [dir.url.appendingPathComponent("a.txt"), dir.url.appendingPathComponent("b b.txt")]
        for url in urls { try Data("x".utf8).write(to: url) }
        withPasteboard { _, adapter in
            let before = adapter.changeCount
            adapter.write(.files(urls))
            #expect(adapter.fileURLs().map(\.standardizedFileURL) == urls.map(\.standardizedFileURL))
            #expect(adapter.types().contains(PasteboardTypes.marker))
            #expect(adapter.changeCount > before)
        }
    }

    @Test func typesUnionAcrossItems() {
        withPasteboard { pb, adapter in
            let first = NSPasteboardItem()
            first.setData(Data("1".utf8), forType: .init("com.example.first"))
            let second = NSPasteboardItem()
            second.setData(Data("2".utf8), forType: .init("com.example.second"))
            pb.clearContents()
            pb.writeObjects([first, second])
            #expect(adapter.types().isSuperset(of: ["com.example.first", "com.example.second"]))
        }
    }

    @Test func declaredSource() {
        withPasteboard { pb, adapter in
            pb.clearContents()
            pb.setString("com.example.editor", forType: .init(PasteboardTypes.source))
            #expect(adapter.declaredSource() == "com.example.editor")
        }
    }
}
