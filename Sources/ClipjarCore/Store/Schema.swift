import GRDB

public enum Schema {
    /// Computed because `DatabaseMigrator` isn't `Sendable`.
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE clip (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  kind TEXT NOT NULL CHECK (kind IN ('text','link','image','file')),
                  plainText TEXT NOT NULL DEFAULT '', previewText TEXT NOT NULL DEFAULT '', searchText TEXT NOT NULL DEFAULT '',
                  rtfData BLOB, htmlData BLOB, imagePath TEXT, imageType TEXT, thumbnailPath TEXT,
                  fileURLs TEXT NOT NULL DEFAULT '[]', contentHash TEXT NOT NULL UNIQUE,
                  sourceBundleID TEXT, sourceAppName TEXT,
                  createdAt DATETIME NOT NULL, lastCopiedAt DATETIME NOT NULL,
                  isPinned BOOLEAN NOT NULL DEFAULT 0, byteSize INTEGER NOT NULL DEFAULT 0,
                  imageWidth INTEGER, imageHeight INTEGER);
                CREATE INDEX clip_lastCopiedAt ON clip(lastCopiedAt DESC);
                CREATE INDEX clip_kind_lastCopiedAt ON clip(kind, lastCopiedAt DESC);
                CREATE INDEX clip_pinned_lastCopiedAt ON clip(isPinned, lastCopiedAt DESC);
                CREATE VIRTUAL TABLE clip_fts USING fts5(searchText, content='clip', content_rowid='id', tokenize='trigram');
                CREATE TRIGGER clip_ai AFTER INSERT ON clip BEGIN
                  INSERT INTO clip_fts(rowid, searchText) VALUES (new.id, new.searchText); END;
                CREATE TRIGGER clip_ad AFTER DELETE ON clip BEGIN
                  INSERT INTO clip_fts(clip_fts, rowid, searchText) VALUES ('delete', old.id, old.searchText); END;
                CREATE TRIGGER clip_au AFTER UPDATE OF searchText ON clip BEGIN
                  INSERT INTO clip_fts(clip_fts, rowid, searchText) VALUES ('delete', old.id, old.searchText);
                  INSERT INTO clip_fts(rowid, searchText) VALUES (new.id, new.searchText); END;
                """)
        }
        return migrator
    }

    public static func configuration() -> Configuration {
        var config = Configuration()
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
            // Sorts and FTS merges must not spill clip text to temp files outside the support directory.
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        return config
    }
}
