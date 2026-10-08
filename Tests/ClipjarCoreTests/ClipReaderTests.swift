import Foundation
import Testing
@testable import ClipjarCore

@MainActor @Suite struct ClipReaderTests {
    private let rtf = Data("{\\rtf1 Hello, Clipjar}".utf8)
    private let html = Data("<b>Hello, Clipjar</b>".utf8)

    private func read(_ pb: FakePasteboard, limits: FilterSettings = FilterSettings()) -> ReadResult {
        ClipReader.read(pb, types: pb.types(), limits: limits)
    }

    private func snapshot(_ result: ReadResult) throws -> PasteboardSnapshot {
        guard case let .snapshot(s) = result else {
            Issue.record("expected snapshot, got \(result)")
            throw CancellationError()
        }
        return s
    }

    @Test func plainText() throws {
        let pb = FakePasteboard()
        pb.copy(types: [PasteboardTypes.string], string: "Hello, Clipjar", declared: "com.example.editor")
        let s = try snapshot(read(pb))
        #expect(s.string == "Hello, Clipjar")
        #expect(s.changeCount == 1)
        #expect(s.types == [PasteboardTypes.string])
        #expect(s.declaredSource == "com.example.editor")
        #expect(pb.reads == [PasteboardTypes.string: 1])
    }

    @Test func textWithRichReps() throws {
        let pb = FakePasteboard()
        pb.copy(
            types: [PasteboardTypes.string, PasteboardTypes.rtf, PasteboardTypes.html], string: "Hello, Clipjar",
            data: [PasteboardTypes.rtf: rtf, PasteboardTypes.html: html]
        )
        let s = try snapshot(read(pb))
        #expect(s.rtf == rtf)
        #expect(s.html == html)
    }

    @Test func oversizedRtfDroppedAlone() throws {
        let pb = FakePasteboard()
        pb.copy(
            types: [PasteboardTypes.string, PasteboardTypes.rtf, PasteboardTypes.html], string: "Hello, Clipjar",
            data: [PasteboardTypes.rtf: Data(count: 2_000_001), PasteboardTypes.html: html]
        )
        let s = try snapshot(read(pb))
        #expect(s.rtf == nil)
        #expect(s.html == html)
        #expect(s.string == "Hello, Clipjar")
    }

    @Test func stringPlusHugeTiffNeverReadsTiff() throws {
        let pb = FakePasteboard()
        pb.copy(
            types: [PasteboardTypes.string, PasteboardTypes.tiff], string: "Hello, Clipjar",
            data: [PasteboardTypes.tiff: Data(count: 60_000_000)]
        )
        let s = try snapshot(read(pb))
        #expect(s.string == "Hello, Clipjar")
        #expect(s.image == nil)
        #expect(pb.reads[PasteboardTypes.tiff] == nil)
    }

    @Test func pngPreferredTiffNeverRead() throws {
        let png = TestImages.png(width: 4, height: 4)
        let pb = FakePasteboard()
        pb.copy(
            types: [PasteboardTypes.png, PasteboardTypes.tiff],
            data: [PasteboardTypes.png: png, PasteboardTypes.tiff: TestImages.tiff(width: 4, height: 4)]
        )
        let s = try snapshot(read(pb))
        #expect(s.image == ImageData(data: png, uti: PasteboardTypes.png))
        #expect(pb.reads[PasteboardTypes.tiff] == nil)
    }

    @Test func tiffReadWhenNoPng() throws {
        let tiff = TestImages.tiff(width: 4, height: 4)
        let pb = FakePasteboard()
        pb.copy(types: [PasteboardTypes.tiff], data: [PasteboardTypes.tiff: tiff])
        #expect(try snapshot(read(pb)).image == ImageData(data: tiff, uti: PasteboardTypes.tiff))
    }

    @Test func giantPngAloneIsOversized() {
        let pb = FakePasteboard()
        pb.copy(types: [PasteboardTypes.png], data: [PasteboardTypes.png: Data(count: 20_000_001)])
        #expect(read(pb) == .oversized)
    }

    @Test func textOverOneMegabyteIsOversized() throws {
        let pb = FakePasteboard()
        pb.copy(types: [PasteboardTypes.string], string: String(repeating: "a", count: 1_000_001))
        #expect(read(pb) == .oversized)
        pb.copy(types: [PasteboardTypes.string], string: String(repeating: "a", count: 1_000_000))
        #expect(try snapshot(read(pb)).string?.utf8.count == 1_000_000)
    }

    @Test func whitespaceStringFallsThroughToImage() throws {
        let png = TestImages.png(width: 4, height: 4)
        let pb = FakePasteboard()
        pb.copy(types: [PasteboardTypes.string, PasteboardTypes.png], string: " \n ", data: [PasteboardTypes.png: png])
        let s = try snapshot(read(pb))
        #expect(s.string == nil)
        #expect(s.image?.data == png)
    }

    @Test func filesWinAndNothingElseRead() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt")]
        let pb = FakePasteboard()
        pb.copy(
            types: [PasteboardTypes.fileURL, PasteboardTypes.string, PasteboardTypes.png], string: "a.txt", urls: urls,
            data: [PasteboardTypes.png: TestImages.png(width: 4, height: 4)]
        )
        let s = try snapshot(read(pb))
        #expect(s.fileURLs == urls)
        #expect(pb.reads[PasteboardTypes.string] == nil)
        #expect(pb.reads[PasteboardTypes.png] == nil)
    }

    @Test func declaredFileURLButEmptyFallsBackToString() throws {
        let pb = FakePasteboard()
        pb.copy(types: [PasteboardTypes.fileURL, PasteboardTypes.string], string: "Hello, Clipjar")
        let s = try snapshot(read(pb))
        #expect(s.fileURLs.isEmpty)
        #expect(s.string == "Hello, Clipjar")
    }

    @Test func nothingUsableIsEmpty() {
        let pb = FakePasteboard()
        pb.copy(types: ["com.example.custom"], data: ["com.example.custom": Data("x".utf8)])
        #expect(read(pb) == .empty)
        #expect(pb.totalDataReads == 0)
    }

    @Test func declaredRepReturningNilIsEmpty() {
        let pb = FakePasteboard()
        pb.copy(types: [PasteboardTypes.png])
        #expect(read(pb) == .empty)
    }
}
