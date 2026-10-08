import Foundation

public enum Highlighter {
    /// Case- and diacritic-insensitive matches of every term, sorted, non-overlapping (earlier start wins;
    /// equal start → longer wins), at most `max`.
    public static func ranges(of terms: [String], in text: String, max: Int = 50) -> [Range<String.Index>] {
        var all: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                all.append(found)
                guard found.upperBound < text.endIndex else { break }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        all.sort { $0.lowerBound != $1.lowerBound ? $0.lowerBound < $1.lowerBound : $0.upperBound > $1.upperBound }
        var kept: [Range<String.Index>] = []
        for range in all where kept.count < max {
            if let last = kept.last, range.lowerBound < last.upperBound { continue }
            kept.append(range)
        }
        return kept
    }
}
