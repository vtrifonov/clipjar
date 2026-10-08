import GRDB

public struct ClipQuery: Sendable, Equatable {
    public var terms: [String]
    public var apps: [String]
    public var kinds: Set<ClipKind>?
    public var pinnedOnly: Bool
    public var limit: Int

    public init(
        terms: [String] = [],
        apps: [String] = [],
        kinds: Set<ClipKind>? = nil,
        pinnedOnly: Bool = false,
        limit: Int = 100
    ) {
        self.terms = terms
        self.apps = apps
        self.kinds = kinds
        self.pinnedOnly = pinnedOnly
        self.limit = limit
    }

    public static let all = ClipQuery()

    public func fetchRows(_ db: Database) throws -> [ClipRow] {
        guard let (whereSQL, arguments) = whereClause() else { return [] }
        var args = arguments
        args += [limit]
        return try ClipRow.fetchAll(
            db,
            sql: """
                SELECT id, kind, previewText, sourceBundleID, sourceAppName, lastCopiedAt, isPinned,
                       thumbnailPath, imageWidth, imageHeight, byteSize,
                       json_array_length(fileURLs) AS fileCount
                FROM clip\(whereSQL)
                ORDER BY lastCopiedAt DESC, id DESC
                LIMIT ?
                """,
            arguments: args
        )
    }

    public func fetchCount(_ db: Database) throws -> Int {
        guard let (whereSQL, arguments) = whereClause() else { return 0 }
        return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip\(whereSQL)", arguments: arguments) ?? 0
    }

    /// nil when the query can match nothing (empty kinds set), so callers skip the database.
    private func whereClause() -> (sql: String, arguments: StatementArguments)? {
        var clauses: [String] = []
        var args = StatementArguments()

        let folded = terms.map(SearchFolding.fold).filter { !$0.isEmpty }
        let longTerms = folded.filter { $0.count >= 3 }
        if !longTerms.isEmpty {
            let match = longTerms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                .joined(separator: " AND ")
            clauses.append("id IN (SELECT rowid FROM clip_fts WHERE clip_fts MATCH ?)")
            args += [match]
        }
        for term in folded where term.count < 3 {
            clauses.append(#"searchText LIKE ? ESCAPE '\'"#)
            args += [Self.likePattern(term)]
        }

        if !apps.isEmpty {
            let perApp = #"(sourceAppName LIKE ? ESCAPE '\' OR sourceBundleID LIKE ? ESCAPE '\')"#
            clauses.append("(" + Array(repeating: perApp, count: apps.count).joined(separator: " OR ") + ")")
            for app in apps {
                let pattern = Self.likePattern(app)
                args += [pattern, pattern]
            }
        }

        if let kinds {
            if kinds.isEmpty { return nil }
            clauses.append("kind IN (" + Array(repeating: "?", count: kinds.count).joined(separator: ", ") + ")")
            for kind in kinds.sorted(by: { $0.rawValue < $1.rawValue }) { args += [kind.rawValue] }
        }

        if pinnedOnly { clauses.append("isPinned = 1") }

        let sql = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        return (sql, args)
    }

    private static func likePattern(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%" + escaped + "%"
    }
}
