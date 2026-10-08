import Testing
@testable import ClipjarCore

@Suite struct SearchFoldingTests {
    @Test func foldsCaseAndDiacritics() {
        #expect(SearchFolding.fold("Café") == SearchFolding.fold("cafe"))
        #expect(SearchFolding.fold("Äpfel").hasPrefix("a"))
        #expect(SearchFolding.fold("ÄPFEL") == SearchFolding.fold("äpfel"))
    }
}
