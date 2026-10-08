import Foundation
import Testing
@testable import ClipjarCore

@Suite struct ImageDecoderTests {
    @Test func downscalesAndNeverUpscales() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("wide.png")
        try TestImages.png(width: 400, height: 200).write(to: url)
        let small = try #require(ImageDecoder.decode(url: url, maxPixelSize: 100))
        #expect(small.width == 100)
        #expect(small.height == 50)
        let full = try #require(ImageDecoder.decode(url: url, maxPixelSize: 1000))
        #expect(full.width == 400)
    }

    @Test func missingFileIsNil() throws {
        let dir = try TempDir()
        #expect(ImageDecoder.decode(url: dir.url.appendingPathComponent("missing.png"), maxPixelSize: 100) == nil)
    }
}
