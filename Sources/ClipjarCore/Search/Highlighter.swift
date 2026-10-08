import Foundation

public enum Highlighter {
    /// Case- and diacritic-insensitive matches of every term, sorted, non-overlapping (earlier start wins;
    /// equal start → longer wins), at most `max`.
    ///
    /// The terms' matches are merged lazily in text order and the search stops once `max` ranges are
    /// kept, so cost follows the visible result rather than the number of matches in a large text.
    public static func ranges(of terms: [String], in text: String, max: Int = 50) -> [Range<String.Index>] {
        var cursors = terms.filter { !$0.isEmpty }.map { TermCursor(term: $0, text: text) }
        var kept: [Range<String.Index>] = []
        while kept.count < max {
            var best: Int?
            for i in cursors.indices {
                guard let candidate = cursors[i].next else { continue }
                if let b = best, let current = cursors[b].next, !precedes(candidate, current) { continue }
                best = i
            }
            guard let b = best, let range = cursors[b].next else { break }
            cursors[b].advance(in: text)
            if let last = kept.last, range.lowerBound < last.upperBound { continue }
            kept.append(range)
        }
        return kept
    }

    private static func precedes(_ a: Range<String.Index>, _ b: Range<String.Index>) -> Bool {
        a.lowerBound != b.lowerBound ? a.lowerBound < b.lowerBound : a.upperBound > b.upperBound
    }

    /// The next not-yet-consumed match of one term.
    private struct TermCursor {
        let term: String
        private(set) var next: Range<String.Index>?

        init(term: String, text: String) {
            self.term = term
            next = Self.find(term, in: text, from: text.startIndex)
        }

        mutating func advance(in text: String) {
            guard let current = next, current.upperBound < text.endIndex else {
                next = nil
                return
            }
            next = Self.find(term, in: text, from: current.upperBound)
        }

        private static func find(_ term: String, in text: String, from start: String.Index) -> Range<String.Index>? {
            text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex)
        }
    }
}
