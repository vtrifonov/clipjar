import Foundation
import Testing
@testable import ClipjarCore

@Suite struct ClipExtractorTests {
    private func snap(
        string: String? = nil, rtf: Data? = nil, html: Data? = nil, image: ImageData? = nil, fileURLs: [URL] = []
    ) -> PasteboardSnapshot {
        PasteboardSnapshot(changeCount: 1, types: [], string: string, rtf: rtf, html: html, image: image, fileURLs: fileURLs)
    }

    @Test func filesKindAndPaths() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b b.txt")]
        let c = try #require(ClipExtractor.extract(snap(fileURLs: urls)))
        #expect(c.kind == .file)
        #expect(c.plainText == "/tmp/a.txt\n/tmp/b b.txt")
        #expect(c.fileURLs == urls)
    }

    @Test func nonFileURLsIgnored() throws {
        let s = snap(string: "https://example.com/docs", fileURLs: [URL(string: "https://example.com")!])
        let c = try #require(ClipExtractor.extract(s))
        #expect(c.kind == .link)
        #expect(c.fileURLs.isEmpty)
    }

    @Test func textKind() throws {
        let c = try #require(ClipExtractor.extract(snap(string: "Hello, Clipjar")))
        #expect(c.kind == .text)
        #expect(c.plainText == "Hello, Clipjar")
    }

    @Test func textKeptUnmodified() throws {
        let c = try #require(ClipExtractor.extract(snap(string: "  Hello,\r\n Clipjar  ")))
        #expect(c.plainText == "  Hello,\r\n Clipjar  ")
    }

    @Test func linkKind() throws {
        #expect(ClipExtractor.extract(snap(string: "https://example.com/docs"))?.kind == .link)
    }

    @Test func wwwLinkKind() throws {
        #expect(ClipExtractor.extract(snap(string: "www.example.com"))?.kind == .link)
    }

    @Test func spacedDomainIsText() throws {
        #expect(ClipExtractor.extract(snap(string: "foo bar.com"))?.kind == .text)
    }

    @Test func mailtoIsText() throws {
        #expect(ClipExtractor.extract(snap(string: "mailto:someone@example.com"))?.kind == .text)
    }

    @Test func richDataKept() throws {
        let rtf = Data("{\\rtf1 Hello, Clipjar}".utf8)
        let html = Data("<b>Hello, Clipjar</b>".utf8)
        let c = try #require(ClipExtractor.extract(snap(string: "Hello, Clipjar", rtf: rtf, html: html)))
        #expect(c.rtf == rtf)
        #expect(c.html == html)
    }

    @Test func oversizedRichDataDropped() throws {
        let c = try #require(ClipExtractor.extract(snap(string: "Hello, Clipjar", rtf: Data(count: 2_000_001))))
        #expect(c.rtf == nil)
    }

    @Test func imageDimensions() throws {
        let png = TestImages.png(width: 40, height: 30)
        let c = try #require(ClipExtractor.extract(snap(image: ImageData(data: png, uti: "public.png"))))
        #expect(c.kind == .image)
        #expect(c.width == 40)
        #expect(c.height == 30)
        #expect(c.image?.uti == "public.png")
        #expect(c.image?.data == png)
    }

    @Test func undecodableImageIsNil() {
        #expect(ClipExtractor.extract(snap(image: ImageData(data: Data("nope".utf8), uti: "public.png"))) == nil)
    }

    @Test func emptyAndWhitespaceAreNil() {
        #expect(ClipExtractor.extract(snap()) == nil)
        #expect(ClipExtractor.extract(snap(string: "")) == nil)
        #expect(ClipExtractor.extract(snap(string: " \n\t ")) == nil)
    }

    @Test func thousandFilesCaptured() throws {
        let urls = (0 ..< 1000).map { URL(fileURLWithPath: "/tmp/clipjar-file-\($0).txt") }
        let c = try #require(ClipExtractor.extract(snap(fileURLs: urls)))
        #expect(c.fileURLs.count == 1000)
        let clip = ClipBuilder.makeClip(from: c, hash: "h", source: nil, now: t0)
        #expect(clip.previewText.count <= 300)
    }
}
