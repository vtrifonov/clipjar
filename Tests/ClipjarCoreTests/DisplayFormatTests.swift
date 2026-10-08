import Foundation
import Testing
@testable import ClipjarCore

@Suite struct DisplayFormatTests {
    private let us = Locale(identifier: "en_US")

    private func row(
        _ preview: String, kind: ClipKind = .text, app: String? = "TextEdit", pinned: Bool = false, fileCount: Int = 0
    ) -> ClipRow {
        ClipRow(
            id: 1, kind: kind, previewText: preview, sourceBundleID: nil, sourceAppName: app, lastCopiedAt: t0,
            isPinned: pinned, thumbnailPath: nil, imageWidth: nil, imageHeight: nil, byteSize: preview.utf8.count,
            fileCount: fileCount
        )
    }

    @Test func countLabel() {
        #expect(DisplayFormat.countLabel(0, locale: us) == "0 clips")
        #expect(DisplayFormat.countLabel(1, locale: us) == "1 clip")
        #expect(DisplayFormat.countLabel(1204, locale: us) == "1,204 clips")
    }

    @Test func relativeTime() {
        #expect(DisplayFormat.relativeTime(t0 - 30, now: t0, locale: us) == "now")
        #expect(DisplayFormat.relativeTime(t0 - 120, now: t0, locale: us).contains("2 min"))
    }

    @Test func secondaryLineText() {
        #expect(DisplayFormat.secondaryLine(row("Hello, Clipjar"), now: t0, locale: us) == "TextEdit · now")
    }

    @Test func secondaryLineLink() {
        let link = row("https://www.example.com/docs", kind: .link, app: "Safari")
        #expect(DisplayFormat.secondaryLine(link, now: t0, locale: us) == "example.com · Safari · now")
    }

    @Test func secondaryLineFiles() {
        let files = row("/tmp/a.txt", kind: .file, app: "Finder", fileCount: 3)
        #expect(DisplayFormat.secondaryLine(files, now: t0, locale: us) == "3 files · Finder · now")
    }

    @Test func secondaryLineWithoutApp() {
        #expect(DisplayFormat.secondaryLine(row("Hello, Clipjar", app: nil), now: t0, locale: us) == "now")
    }

    @Test func previewSummaryText() {
        let lines = (0..<37).map { _ in String(repeating: "a", count: 31) }.joined(separator: "\n")
        let text = lines + String(repeating: "b", count: 1204 - lines.count)
        #expect(text.count == 1204)
        let clip = Clip.make(text)
        #expect(DisplayFormat.previewSummary(clip, locale: us) == "Text · 1,204 characters · 37 lines")
        #expect(DisplayFormat.previewSummary(Clip.make("a"), locale: us) == "Text · 1 character · 1 line")
    }

    @Test func previewSummaryCRLFIsOneLineBreak() {
        #expect(DisplayFormat.previewSummary(Clip.make("a\r\nb"), locale: us) == "Text · 3 characters · 2 lines")
    }

    @Test func previewSummaryTrailingNewlineAddsNoLine() {
        #expect(DisplayFormat.previewSummary(Clip.make("hello\n"), locale: us) == "Text · 6 characters · 1 line")
        #expect(DisplayFormat.previewSummary(Clip.make("a\r\nb\r\n"), locale: us) == "Text · 4 characters · 2 lines")
        #expect(DisplayFormat.previewSummary(Clip.make("a\n\n"), locale: us) == "Text · 3 characters · 2 lines")
    }

    @Test func previewSummaryLink() {
        let clip = Clip.make("https://example.com/docs", kind: .link)
        #expect(DisplayFormat.previewSummary(clip, locale: us) == "Link · example.com")
    }

    @Test func previewSummaryImage() {
        var clip = Clip.make("", kind: .image)
        clip.imageWidth = 1200
        clip.imageHeight = 800
        clip.byteSize = 245_000
        #expect(DisplayFormat.previewSummary(clip, locale: us) == "Image · 1200 × 800 px · 245 KB")
    }

    @Test func previewSummaryFiles() {
        var clip = Clip.make("/tmp/a.txt", kind: .file)
        clip.fileURLs = ["file:///tmp/a.txt"]
        #expect(DisplayFormat.previewSummary(clip, locale: us) == "1 file")
        clip.fileURLs += ["file:///tmp/b.txt", "file:///tmp/c.txt"]
        #expect(DisplayFormat.previewSummary(clip, locale: us) == "3 files")
    }

    @Test func footerHints() {
        let paste = "⏎ Paste  ⌥⏎ Copy  ⌘P Pin  ⌘⌫ Delete  ⇥ Filter"
        let copy = "⏎ Copy  ⌘P Pin  ⌘⌫ Delete  ⇥ Filter"
        #expect(DisplayFormat.footerHints(pasteOnSelect: true, trusted: true, selectedPinned: false) == paste)
        #expect(DisplayFormat.footerHints(pasteOnSelect: false, trusted: true, selectedPinned: false) == copy)
        #expect(DisplayFormat.footerHints(pasteOnSelect: true, trusted: false, selectedPinned: false) == copy)
        let pinned = DisplayFormat.footerHints(pasteOnSelect: true, trusted: true, selectedPinned: true)
        #expect(pinned.contains("⌘P Unpin"))
        #expect(!pinned.contains("⌘P Pin "))
    }

    @Test func rowAccessibilityLabel() {
        let label = DisplayFormat.rowAccessibilityLabel(row("Hello, Clipjar", pinned: true), now: t0, locale: us)
        #expect(label == "Text, Hello, Clipjar, from TextEdit, now, pinned")
        let long = String(repeating: "x", count: 150)
        let truncated = DisplayFormat.rowAccessibilityLabel(row(long), now: t0, locale: us)
        #expect(truncated == "Text, \(String(repeating: "x", count: 100)), from TextEdit, now")
        let files = DisplayFormat.rowAccessibilityLabel(row("/tmp/a.txt", kind: .file, app: nil), now: t0, locale: us)
        #expect(files == "Files, /tmp/a.txt, now")
    }

    @Test func rowAccessibilityLabelNamesHexColour() {
        let label = DisplayFormat.rowAccessibilityLabel(row("#f80"), now: t0, locale: us)
        #expect(label == "Text, #f80, colour #FF8800, from TextEdit, now")
        let link = DisplayFormat.rowAccessibilityLabel(row("https://example.com/docs", kind: .link), now: t0, locale: us)
        #expect(!link.contains("colour"))
    }

    @Test func colourHex() {
        #expect(DisplayFormat.colourHex(TextHeuristics.RGBA(r: 1, g: 136.0 / 255, b: 0, a: 1)) == "#FF8800")
        #expect(DisplayFormat.colourHex(TextHeuristics.RGBA(r: 0, g: 0, b: 0, a: 0.5)) == "#000000")
    }

    @Test func bytes() {
        #expect(DisplayFormat.bytes(245_000) == "245 KB")
    }
}
