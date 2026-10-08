import Foundation
import Testing
@testable import ClipjarCore

@Suite struct ClipBuilderTests {
    @Test func fileClip() {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b b.txt")]
        let c = CapturedContent(kind: .file, plainText: "", fileURLs: urls)
        let clip = ClipBuilder.makeClip(from: c, hash: "h", source: textEdit, now: t0)
        #expect(clip.kind == .file)
        #expect(clip.plainText == "/tmp/a.txt\n/tmp/b b.txt")
        #expect(clip.previewText == "a.txt, b b.txt")
        #expect(clip.fileURLs == urls.map(\.absoluteString))
        #expect(clip.searchText == SearchFolding.fold(clip.plainText))
        #expect(clip.byteSize == 0)
    }

    @Test func imageClip() {
        let data = TestImages.png(width: 40, height: 30)
        let c = CapturedContent(
            kind: .image, plainText: "", image: ImageData(data: data, uti: "public.png"), width: 40, height: 30
        )
        let clip = ClipBuilder.makeClip(from: c, hash: "h", source: nil, now: t0)
        #expect(clip.previewText == "Image 40\u{00D7}30")
        #expect(clip.plainText == "")
        #expect(clip.searchText == "")
        #expect(clip.imageType == "public.png")
        #expect(clip.imageWidth == 40)
        #expect(clip.imageHeight == 30)
        #expect(clip.byteSize == data.count)
        #expect(clip.imagePath == nil)
        #expect(clip.thumbnailPath == nil)
        #expect(clip.sourceAppName == nil)
    }

    @Test func textClip() {
        let rtf = Data("{\\rtf1 synthetic}".utf8)
        let c = text("Hello,\n Clipjar", rtf: rtf)
        let clip = ClipBuilder.makeClip(from: c, hash: "h", source: textEdit, now: t0)
        #expect(clip.kind == .text)
        #expect(clip.plainText == "Hello,\n Clipjar")
        #expect(clip.previewText == "Hello, Clipjar")
        #expect(clip.byteSize == 15)
        #expect(clip.searchText == SearchFolding.fold("Hello,\n Clipjar"))
        #expect(clip.rtfData == rtf)
        #expect(clip.htmlData == nil)
        #expect(clip.contentHash == "h")
        #expect(clip.createdAt == t0)
        #expect(clip.lastCopiedAt == t0)
        #expect(clip.isPinned == false)
        #expect(clip.sourceBundleID == "com.apple.TextEdit")
        #expect(clip.sourceAppName == "TextEdit")
    }
}
