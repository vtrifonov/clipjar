import Foundation
import GRDB
import Testing
@testable import ClipjarCore

@Suite struct ClipStoreIngestTests {
    private func id(of result: IngestResult) -> Int64 {
        switch result {
        case let .inserted(id), let .bumped(id): id
        }
    }

    @Test(arguments: Backend.allCases)
    func insertsText(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let result = try await fx.store.ingest(text("Hello, Clipjar"), source: textEdit, at: t0)
        guard case let .inserted(id) = result else {
            Issue.record("expected .inserted, got \(result)")
            return
        }
        let clip = try #require(try fetchClip(fx.writer, id))
        #expect(clip.kind == .text)
        #expect(clip.createdAt == t0)
        #expect(clip.lastCopiedAt == t0)
        #expect(clip.isPinned == false)
    }

    @Test(arguments: Backend.allCases)
    func insertsLinkAndFile(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let link = try await fx.store.ingest(text("https://example.com/docs", kind: .link), source: safari, at: t0)
        let files = CapturedContent(
            kind: .file, plainText: "",
            fileURLs: [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b b.txt")]
        )
        let file = try await fx.store.ingest(files, source: nil, at: t0 + 1)
        #expect(try fetchClip(fx.writer, id(of: link))?.kind == .link)
        let fileClip = try #require(try fetchClip(fx.writer, id(of: file)))
        #expect(fileClip.kind == .file)
        #expect(fileClip.fileURLs.count == 2)
    }

    @Test(arguments: Backend.allCases)
    func bumpUpdatesRecencyAndSource(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let first = try await fx.store.ingest(text("Hello, Clipjar"), source: textEdit, at: t0)
        try await fx.writer.write { try $0.execute(sql: "UPDATE clip SET isPinned = 1") }
        let second = try await fx.store.ingest(text("Hello, Clipjar"), source: safari, at: t0 + 60)
        #expect(second == .bumped(id(of: first)))
        let clip = try #require(try fetchClip(fx.writer, id(of: first)))
        #expect(clip.lastCopiedAt == t0 + 60)
        #expect(clip.sourceAppName == "Safari")
        #expect(clip.sourceBundleID == "com.apple.Safari")
        #expect(clip.createdAt == t0)
        #expect(clip.isPinned == true)
        #expect(try clipCount(fx.writer) == 1)
    }

    @Test(arguments: Backend.allCases)
    func bumpWithNilSourceKeepsSource(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let first = try await fx.store.ingest(text("Hello, Clipjar"), source: textEdit, at: t0)
        try await fx.store.ingest(text("Hello, Clipjar"), source: nil, at: t0 + 60)
        let clip = try #require(try fetchClip(fx.writer, id(of: first)))
        #expect(clip.sourceAppName == "TextEdit")
        #expect(clip.sourceBundleID == "com.apple.TextEdit")
    }

    @Test(arguments: Backend.allCases)
    func bumpFillsOnlyMissingRichData(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let a = Data("{\\rtf1 A}".utf8)
        let b = Data("{\\rtf1 B}".utf8)
        let first = try await fx.store.ingest(text("Hello, Clipjar"), source: textEdit, at: t0)
        try await fx.store.ingest(text("Hello, Clipjar", rtf: a), source: textEdit, at: t0 + 1)
        #expect(try fetchClip(fx.writer, id(of: first))?.rtfData == a)
        try await fx.store.ingest(text("Hello, Clipjar", rtf: b), source: textEdit, at: t0 + 2)
        #expect(try fetchClip(fx.writer, id(of: first))?.rtfData == a)
    }

    @Test(arguments: Backend.allCases)
    func sameTextDifferentKindIsTwoRows(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let a = try await fx.store.ingest(text("https://example.com", kind: .text), source: nil, at: t0)
        let b = try await fx.store.ingest(text("https://example.com", kind: .link), source: nil, at: t0 + 1)
        #expect(a == .inserted(id(of: a)))
        #expect(b == .inserted(id(of: b)))
        #expect(try clipCount(fx.writer) == 2)
    }

    @Test(arguments: Backend.allCases)
    func crlfVariantBumps(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        let first = try await fx.store.ingest(text("a\r\nb"), source: nil, at: t0)
        let second = try await fx.store.ingest(text("a\nb"), source: nil, at: t0 + 1)
        #expect(second == .bumped(id(of: first)))
    }

    @Test(arguments: Backend.allCases)
    func bumpDoesNotTouchFTS(_ backend: Backend) async throws {
        let fx = try makeStore(backend)
        try await fx.store.ingest(text("Hello, Clipjar"), source: textEdit, at: t0)
        try await fx.store.ingest(text("Hello, Clipjar"), source: safari, at: t0 + 60)
        let rows = try await fx.writer.read { try ClipQuery(terms: ["hello"]).fetchRows($0) }
        #expect(rows.count == 1)
    }
}
