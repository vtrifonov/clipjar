import GRDB
import Testing

@Suite struct SQLiteCapabilityTests {
    @Test func sqliteVersionSupportsTrigram() throws {
        let db = try DatabaseQueue()
        let version = try db.read { try String.fetchOne($0, sql: "SELECT sqlite_version()") } ?? ""
        let parts = version.split(separator: ".").compactMap { Int($0) }
        #expect(parts.count >= 2)
        let major = parts.first ?? 0
        let minor = parts.count > 1 ? parts[1] : 0
        #expect(major > 3 || (major == 3 && minor >= 34))
    }

    @Test func trigramTokenizerAvailable() throws {
        let db = try DatabaseQueue()
        let count = try db.write { db -> Int in
            try db.execute(sql: "CREATE VIRTUAL TABLE t USING fts5(x, tokenize='trigram')")
            try db.execute(sql: "INSERT INTO t(x) VALUES (?)", arguments: ["Hello, Clipjar"])
            return try Int.fetchOne(db, sql: #"SELECT count(*) FROM t WHERE t MATCH '"lipj"'"#) ?? 0
        }
        #expect(count == 1)
    }
}
