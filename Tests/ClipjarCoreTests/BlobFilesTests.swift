import Foundation
import Testing
@testable import ClipjarCore

@Suite struct BlobFilesTests {
    @Test func writeIfAbsentCreatesPrivateFile() throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let blobs = BlobFiles(directory: dir.url)
        let created = try blobs.writeIfAbsent(Data([1, 2, 3]), name: "a.png")
        #expect(created)
        #expect(blobs.exists("a.png"))
        #expect(try posixPermissions(blobs.url("a.png")) == 0o600)
        #expect(blobs.read("a.png") == Data([1, 2, 3]))
    }

    @Test func writeIfAbsentDoesNotOverwrite() throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let blobs = BlobFiles(directory: dir.url)
        #expect(try blobs.writeIfAbsent(Data([1]), name: "a.png"))
        #expect(try blobs.writeIfAbsent(Data([9, 9]), name: "a.png") == false)
        #expect(blobs.read("a.png") == Data([1]))
    }

    @Test func removeIgnoresMissing() throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let blobs = BlobFiles(directory: dir.url)
        _ = try blobs.writeIfAbsent(Data([1]), name: "keep.png")
        blobs.remove(["nope.png"])
        #expect(blobs.exists("keep.png"))
        blobs.remove(["keep.png", "nope.png"])
        #expect(!blobs.exists("keep.png"))
    }

    @Test func names() {
        #expect(BlobFiles.imageName(hash: "ab", uti: "public.png") == "ab.png")
        #expect(BlobFiles.imageName(hash: "ab", uti: "public.tiff") == "ab.tiff")
        #expect(BlobFiles.thumbnailName(hash: "ab") == "ab.thumb.png")
    }

    @Test func thumbnailLongestEdge112() throws {
        let thumb = try #require(BlobFiles.thumbnail(for: TestImages.png(width: 400, height: 200)))
        let size = try #require(TestImages.pixelSize(of: thumb))
        #expect(size.width == 112 && size.height == 56)
    }

    @Test func thumbnailNeverUpscales() throws {
        let thumb = try #require(BlobFiles.thumbnail(for: TestImages.png(width: 50, height: 20)))
        let size = try #require(TestImages.pixelSize(of: thumb))
        #expect(size.width == 50 && size.height == 20)
    }

    @Test func thumbnailExtremeAspect() throws {
        let thumb = try #require(BlobFiles.thumbnail(for: TestImages.png(width: 1, height: 4_000)))
        let size = try #require(TestImages.pixelSize(of: thumb))
        #expect(size.height == 112)
        #expect(size.width >= 1)
    }

    @Test func thumbnailOfGarbageIsNil() {
        #expect(BlobFiles.thumbnail(for: Data("not an image".utf8)) == nil)
    }
}
