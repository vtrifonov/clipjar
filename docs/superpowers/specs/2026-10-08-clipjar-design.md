# Clipjar — Design Spec (v1)

- **Date:** 2026-10-08
- **Status:** Approved design brief → implementation spec
- **Repo:** github.com/vtrifonov/clipjar (MIT, public)
- **Toolchain:** Xcode 27 / Swift 6.4 on macOS 26 (dev). **Deployment target: macOS 14.0.**

Requirements are numbered `R<n>`. "MUST" = required for v1. Decisions marked *(spec decision)* were
not in the brief and were fixed here so the implementer does not have to invent them. R80+ were added
after the spec review panel; where an R80+ requirement amends an earlier one, the earlier text has
been updated in place and points to it.

---

## 1. Overview, goals, non-goals

Clipjar is a native macOS menu bar clipboard history manager. It records text (with rich-text
originals), links, images and Finder files that the user copies, and lets them find and paste any
previous clip from a keyboard-first floating panel opened by a menu bar click or a global hotkey.

**Goals**
- R1. Native Swift 6 / SwiftUI + AppKit app, macOS 14+, built with SwiftPM + Makefile (no `.xcodeproj`).
- R2. Best-in-class UX: panel visible < 50 ms after hotkey, keyboard-first, instant search, smooth at 10k clips.
- R3. Local-only, privacy-respecting capture (concealed types, ignore list, pause).
- R4. Runs on any Mac (Apple silicon + Intel) from a downloaded zip or `make install`; no user-specific paths.

**Non-goals (explicitly out of scope for v1)**
- R5. No iCloud/network sync, no encryption at rest, no snippets/templates editor, no editing clips,
  no App Store build/sandboxing, no Developer ID signing or notarization, no auto-update (Sparkle),
  no custom app icon artwork (generic app icon; menu bar uses an SF Symbol) *(spec decision)*,
  no localisation beyond English, no plain-text-paste transform mode.

---

## 2. Package layout and build

### 2.1 Files

```
Package.swift
Makefile
Resources/Info.plist                    # template; version keys filled by make
Sources/ClipjarCore/                    # library: all logic, unit-tested
  Model/        Clip.swift ClipRow.swift ClipKind.swift SourceApp.swift
  Capture/      PasteboardReading.swift NSPasteboardAdapter.swift ClipReader.swift ClipExtractor.swift
                ClipFilter.swift ClipboardWatcher.swift
  App/          InstanceLock.swift
  Store/        ClipStore.swift Schema.swift ClipQuery.swift BlobFiles.swift StoreOpener.swift
  Search/       QueryParser.swift Highlighter.swift TextHeuristics.swift SearchFolding.swift
  Paste/        Paster.swift
  UIModel/      HistoryViewModel.swift PanelCommand.swift PanelKeyMap.swift PanelPlacement.swift
  Settings/     SettingsStore.swift
Sources/Clipjar/                        # executable: thin AppKit/SwiftUI shell
  main.swift AppDelegate.swift StatusItemController.swift PanelController.swift
  HotkeyController.swift SettingsWindowController.swift MainMenu.swift
  Views/ HistoryView.swift ClipRowView.swift PreviewView.swift FilterBar.swift
         BannerView.swift SettingsView.swift VisualEffectBackground.swift
Tests/ClipjarCoreTests/                 # swift-testing
.github/workflows/ci.yml  .github/workflows/release.yml
README.md
```

### 2.2 Package.swift

- R6. `// swift-tools-version: 6.2`, `platforms: [.macOS(.v14)]`, Swift 6 language mode for all our targets.
- R7. Dependencies pinned with `exact:` (both verified to exist on 2026-10-08, both MIT):
  - `https://github.com/sindresorhus/KeyboardShortcuts` **exact `3.1.0`** (tools 6.2, macOS 10.15+, Swift 6
    native, MainActor default isolation). Note the 3.x API uses `Name("…", initial:)` (not `default:`).
  - `https://github.com/groue/GRDB.swift` **exact `7.11.1`** (tools 6.1, macOS 10.15+, Swift 6 mode,
    defines `SQLITE_ENABLE_FTS5`).
- R8. Targets:
  - `ClipjarCore` (library) → depends on `GRDB`. Imports AppKit/ApplicationServices where needed
    (pasteboard adapter, Paster), but has **no** SwiftUI views and no KeyboardShortcuts dependency.
  - `Clipjar` (executableTarget) → depends on `ClipjarCore`, `KeyboardShortcuts`;
    `swiftSettings: [.defaultIsolation(MainActor.self)]`.
  - `ClipjarCoreTests` (testTarget) → depends on `ClipjarCore`; uses `import Testing`.
- R9. KeyboardShortcuts ships a SwiftPM resource bundle (`KeyboardShortcuts_KeyboardShortcuts.bundle`,
  localised strings used by the Recorder). The generated accessor (verified with this toolchain) looks
  in `Bundle.main.resourceURL` first, so the `.app` MUST contain every `*.bundle` from the build
  products dir under `Contents/Resources/`. Without it the Recorder crashes with
  `fatalError("unable to find bundle…")`. The Recorder and global hotkey therefore only work when run
  as the assembled `.app`, never via `swift run`.

### 2.3 Makefile

- R10. Variables (overridable): `CONFIG ?= release`, `VERSION ?= 0.1.0`, `BUILD_NUMBER ?= 1`,
  `ARCHS ?= --arch arm64 --arch x86_64`, `INSTALL_DIR ?= /Applications`, `APP = build/Clipjar.app`.
  `BIN_DIR := $(shell swift build -c $(CONFIG) $(ARCHS) --show-bin-path)`. No absolute user paths.
- R11. Targets:

| Target | Behaviour |
|---|---|
| `build` | `swift build -c $(CONFIG) $(ARCHS)` (universal) |
| `test` | `swift test` (host arch, debug) |
| `app` | depends on `build`; `rm -rf $(APP)`; create `Contents/{MacOS,Resources}`; copy `$(BIN_DIR)/Clipjar` → `Contents/MacOS/Clipjar`; copy `$(BIN_DIR)/*.bundle` → `Contents/Resources/`; copy `Resources/Info.plist` → `Contents/Info.plist` then `plutil -replace CFBundleShortVersionString -string $(VERSION)` and `CFBundleVersion -string $(BUILD_NUMBER)`; `lipo -archs` check prints both archs (fail if not both) |
| `sign` | depends on `app`; `codesign --force --deep -s - $(APP)`; `codesign --verify --deep --strict $(APP)` |
| `zip` | depends on `sign`; `ditto -c -k --keepParent $(APP) build/Clipjar.zip` |
| `install` | depends on `sign`; quit running Clipjar (`pkill -x Clipjar \|\| true`); `rm -rf $(INSTALL_DIR)/Clipjar.app`; `ditto $(APP) $(INSTALL_DIR)/Clipjar.app` |
| `clean` | `rm -rf .build build` |

- R12. `Resources/Info.plist` keys: `CFBundleIdentifier=com.vtrifonov.clipjar`, `CFBundleName=Clipjar`,
  `CFBundleDisplayName=Clipjar`, `CFBundleExecutable=Clipjar`, `CFBundlePackageType=APPL`,
  `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion=14.0`, `LSUIElement=YES`,
  `NSPrincipalClass=NSApplication`, `LSApplicationCategoryType=public.app-category.productivity`,
  `NSAppSleepDisabled=YES` (keeps the 300 ms poll from being napped; see also R85),
  `NSHumanReadableCopyright="© 2026 Vasil Trifonov. MIT License."`. No entitlements file.

---

## 3. Data model and persistence

### 3.1 Types (ClipjarCore, all `Sendable`)

```swift
public enum ClipKind: String, Codable, Sendable, CaseIterable { case text, link, image, file }

public struct SourceApp: Sendable, Equatable { public var bundleID: String?; public var name: String? }

public struct Clip: Identifiable, Sendable, Equatable, Codable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var kind: ClipKind
    public var plainText: String        // text/link: the text; file: paths joined by "\n"; image: ""
    public var previewText: String      // whitespace-collapsed, trimmed, first 300 chars (see R16)
    public var searchText: String       // SearchFolding.fold(plainText) (R80)
    public var rtfData: Data?           // public.rtf original, text/link only
    public var htmlData: Data?          // public.html original, text/link only
    public var imagePath: String?       // relative to blobs dir, e.g. "<hash>.png"
    public var imageType: String?       // UTI of stored image: "public.png" | "public.tiff"
    public var thumbnailPath: String?   // relative, "<hash>.thumb.png"
    public var fileURLs: [String]       // absolute file:// URL strings, order preserved (JSON text column)
    public var contentHash: String      // lowercase hex SHA-256
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var createdAt: Date
    public var lastCopiedAt: Date
    public var isPinned: Bool
    public var byteSize: Int            // text: UTF-8 bytes of plainText; image: raw bytes; file: 0
    public var imageWidth: Int?
    public var imageHeight: Int?
}

/// Lightweight projection for list rows (never loads plainText beyond previewText, rtf, html).
public struct ClipRow: Identifiable, Sendable, Equatable, FetchableRecord, Decodable {
    public var id: Int64; public var kind: ClipKind; public var previewText: String
    public var sourceBundleID: String?; public var sourceAppName: String?
    public var lastCopiedAt: Date; public var isPinned: Bool
    public var thumbnailPath: String?; public var imageWidth: Int?; public var imageHeight: Int?
    public var byteSize: Int
}
```

### 3.2 Schema (GRDB `DatabaseMigrator`, migration `"v1"`)

- R13. Migrations registered in `Schema.migrator` (a static `DatabaseMigrator`); `eraseDatabaseOnSchemaChange`
  is **off**. Future changes add migrations `"v2"`, … only.

```sql
CREATE TABLE clip (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  kind           TEXT    NOT NULL CHECK (kind IN ('text','link','image','file')),
  plainText      TEXT    NOT NULL DEFAULT '',
  previewText    TEXT    NOT NULL DEFAULT '',
  searchText     TEXT    NOT NULL DEFAULT '',
  rtfData        BLOB,
  htmlData       BLOB,
  imagePath      TEXT,
  imageType      TEXT,
  thumbnailPath  TEXT,
  fileURLs       TEXT    NOT NULL DEFAULT '[]',
  contentHash    TEXT    NOT NULL UNIQUE,
  sourceBundleID TEXT,
  sourceAppName  TEXT,
  createdAt      DATETIME NOT NULL,
  lastCopiedAt   DATETIME NOT NULL,
  isPinned       BOOLEAN NOT NULL DEFAULT 0,
  byteSize       INTEGER NOT NULL DEFAULT 0,
  imageWidth     INTEGER,
  imageHeight    INTEGER
);
CREATE INDEX clip_lastCopiedAt ON clip(lastCopiedAt DESC);
CREATE INDEX clip_kind_lastCopiedAt ON clip(kind, lastCopiedAt DESC);
CREATE INDEX clip_pinned_lastCopiedAt ON clip(isPinned, lastCopiedAt DESC);

CREATE VIRTUAL TABLE clip_fts USING fts5(
  searchText, content='clip', content_rowid='id', tokenize='trigram'
);
CREATE TRIGGER clip_ai AFTER INSERT ON clip BEGIN
  INSERT INTO clip_fts(rowid, searchText) VALUES (new.id, new.searchText); END;
CREATE TRIGGER clip_ad AFTER DELETE ON clip BEGIN
  INSERT INTO clip_fts(clip_fts, rowid, searchText) VALUES ('delete', old.id, old.searchText); END;
CREATE TRIGGER clip_au AFTER UPDATE OF searchText ON clip BEGIN
  INSERT INTO clip_fts(clip_fts, rowid, searchText) VALUES ('delete', old.id, old.searchText);
  INSERT INTO clip_fts(rowid, searchText) VALUES (new.id, new.searchText); END;
```

- R14. FTS uses the `trigram` tokenizer (SQLite ≥ 3.34; macOS 14 ships 3.43) so search is
  case-insensitive **substring** matching, which `unicode61` cannot do. Created with raw SQL
  (`db.execute(sql:)`) so we do not depend on GRDB's FTS5 Swift DSL. `contentHash` is `UNIQUE`
  (the dedup key) and is unique **across kinds** because kind is part of the hashed input (R17).
- R80. **Folded search text.** `SearchFolding.fold(_:)` = `s.folding(options: [.caseInsensitive,
  .diacriticInsensitive], locale: nil)`. `searchText = fold(plainText)` is written on insert; FTS and the
  short-term `LIKE` run on `searchText`, and every query term is folded the same way before matching, so
  `cafe` finds "Café" and `ä` finds "Äpfel", consistent with the highlighter (R52).

### 3.3 Classification, normalisation, link detection, dedup

- R15. **Extraction priority** (`ClipExtractor.extract(_ snapshot) -> CapturedContent?`, pure; the same
  order drives which representations `ClipReader` reads at all, R81):
  1. If `fileURLs` non-empty (only `file:` URLs) → `.file`; `plainText` = paths joined by `"\n"`.
  2. Else if plain string present and contains a non-whitespace character → `.text` or `.link` (R18),
     carrying `rtfData`/`htmlData` if present; rich data larger than 2 MB each is dropped (plain kept).
  3. Else if image data present (`public.png` preferred, else `public.tiff`) → `.image`; width/height read
     via `CGImageSourceCopyPropertiesAtIndex` (`kCGImagePropertyPixelWidth/Height`). Undecodable image → `nil`.
  4. Else → `nil` (nothing captured).
- R16. `previewText` = `plainText` with every run of Unicode whitespace/newlines replaced by one space,
  trimmed, truncated to 300 characters (grapheme-safe). For files: last path components joined by ", ".
  For images: `"Image W×H"`.
- R17. **Dedup hash** = SHA-256 (CryptoKit) of `kind.rawValue + "\u{0}" + normalisedContent`, where:
  text/link → `plainText` with `\r\n`/`\r` → `\n` only (no trimming, so `echo hi` and `echo hi\n` are
  distinct clips);
  image → raw stored image bytes; file → URL strings joined by `"\n"` (order preserved).
  RTF/HTML and source app are **not** part of the hash.
- R18. **Link rule** (`TextHeuristics.isLink`): trimmed text has no whitespace, length ≤ 2,048, and either
  `URL(string:)` parses with scheme `http`/`https` and a non-empty host, or it starts with `www.` and
  `URL(string: "https://" + text)` has a host containing a dot. Display domain = host with leading
  `www.` removed.
- R19. **Bump to top** on a dedup hit (hash exists): in one write transaction set
  `lastCopiedAt = now`, `sourceBundleID`/`sourceAppName` = new source (if non-nil), and fill
  `rtfData`/`htmlData` only where the existing value is `NULL` and the new capture has one.
  `createdAt`, `isPinned`, `plainText` are unchanged. Blob names are hash-derived, so normally no blob is
  written; **exception (image bump):** missing blob/thumbnail files are repaired. Placement (N7): file IO
  happens **before** the transaction — R31 pre-writes `blobs/<hash>.<ext>` / `<hash>.thumb.png` whenever
  they are absent on disk — and the bump inside the transaction sets `imagePath`/`thumbnailPath` if they
  are `NULL`. No file IO happens inside the write transaction.
- R20. **Colour swatch rule** (`TextHeuristics.hexColor`): trimmed text matches
  `^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$` → returns RGBA components (cut item #2).
- R21. **Code-like rule** (`TextHeuristics.isCodeLike`) for SF Mono in rows: true if text contains any of
  `{`, `};`, `=>`, `</`, `#include`, `func `, `def `, or ≥ 2 lines of which ≥ 1 starts with a tab or 4 spaces.

### 3.4 Storage location and files

- R22. Support dir = `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, …)`
  `/Clipjar/` (resolved at runtime; never hardcoded). Contents: `clips.sqlite` (+ `-wal`, `-shm`),
  `blobs/`. Dir and `blobs/` created with POSIX `0700`, re-applied at every launch. `clips.sqlite` is
  created empty with `0600` (`FileManager.createFile(atPath:contents:attributes:)`) **before** the pool
  opens, so SQLite's `-wal`/`-shm` inherit `0600`; blob files set to `0600` after writing. The support
  dir gets `URLResourceValues.isExcludedFromBackup = true` at every launch (no clips in Time Machine).
- R23. Blob names: `blobs/<contentHash>.png|.tiff` (original bytes) and `blobs/<contentHash>.thumb.png`
  (longest edge 112 px, generated with `CGImageSourceCreateThumbnailAtIndex`,
  `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform`).
  Written atomically (`Data.write(to:options: .atomic)`).

---

## 4. Units: interfaces and behaviour

All signatures are normative in shape; parameter labels may be adjusted if behaviour is unchanged.

### 4.1 Pasteboard abstraction

```swift
public enum PasteboardTypes {
    public static let marker    = "com.vtrifonov.clipjar.marker"       // written by Clipjar on paste
    public static let concealed = "org.nspasteboard.ConcealedType"
    public static let transient = "org.nspasteboard.TransientType"
    public static let autoGen   = "org.nspasteboard.AutoGeneratedType"
    public static let source    = "org.nspasteboard.source"            // optional source bundle id
}
public enum SensitiveTypes {   // legacy/proprietary markers, rejected as `.concealed` (R27)
    public static let all: Set<String> = ["com.agilebits.onepassword", "net.antelle.keeweb",
        "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping", "Pasteboard generator type"]
}
public struct ImageData: Sendable, Equatable { public var data: Data; public var uti: String }
public struct PasteboardSnapshot: Sendable, Equatable {   // output of ClipReader, only chosen reps filled
    public var changeCount: Int
    public var types: Set<String>         // union across all items
    public var string: String?            // public.utf8-plain-text of first item
    public var rtf: Data?; public var html: Data?
    public var image: ImageData?
    public var fileURLs: [URL]
    public var declaredSource: String?
}
public enum ClipPayload: Sendable, Equatable {
    case text(plain: String, rtf: Data?, html: Data?)
    case image(ImageData)
    case files([URL])
}
@MainActor public protocol PasteboardReading: AnyObject {   // thin; no policy
    var changeCount: Int { get }
    func types() -> Set<String>                 // metadata only, no data read
    func declaredSource() -> String?            // org.nspasteboard.source (metadata string)
    func fileURLs() -> [URL]                    // readObjects(forClasses: [NSURL], fileURLsOnly)
    func string() -> String?
    func data(forType type: String) -> Data?
}
public enum ReadResult: Sendable, Equatable { case snapshot(PasteboardSnapshot), oversized, empty }
@MainActor public enum ClipReader {
    public static func read(_ pb: PasteboardReading, types: Set<String>, limits: FilterSettings) -> ReadResult
}
@MainActor public protocol PasteboardWriting: AnyObject {
    func write(_ payload: ClipPayload)   // clearContents + one item + marker type (empty Data)
}
@MainActor public final class SystemPasteboard: PasteboardReading, PasteboardWriting { init(_ pb: NSPasteboard = .general) }
```

- R24. Limits apply only to the **chosen primary payload**: text > 1 MB UTF-8 or chosen image > 20 MB →
  `oversized`; RTF/HTML > 2 MB → that rep alone is dropped. Unread reps can't cause a rejection (R81).
- R81. **Read order (D5/D6).** Capture is two-phase:
  1. *Preflight* (`ClipFilter.preflight`, R26) uses only `changeCount`, `types()` and `declaredSource()` —
     **zero content-data reads** — so paused, ignored, concealed and own-write clips are never pulled into
     Clipjar's memory.
  2. *Read* (`ClipReader.read`) fetches only the representation R15 will use: if `public.file-url` in types →
     `fileURLs()`; if that returns non-empty, stop, else fall through (A26); then if a string type is present → `string()`, and if it has non-whitespace,
     `rtf`/`html` (each ≤ 2 MB, dropped individually) and stop; else `public.png` if present (TIFF is
     **never** read when PNG exists), else `public.tiff`. Image data is read only when there are no files
     and no non-whitespace string. Returns `.oversized` / `.empty` / `.snapshot`.
  The read stays on the main actor (NSPasteboard is not Sendable); this is a documented, bounded-by-
  limits cost paid only for accepted clips.
- R25. `write(.text)` sets `.string`, plus `.rtf`/`.html` when present; `write(.image)` sets data for its
  UTI; `write(.files)` uses `writeObjects(urls as [NSURL])` then adds the marker to the first item.
  Every write includes the marker type.

### 4.2 ClipFilter (pure)

```swift
public struct FilterSettings: Sendable, Equatable {
    public var ignoredBundleIDs: Set<String>; public var pausedUntil: Date?; public var isPaused: Bool
    public var maxTextBytes = 1_000_000; public var maxImageBytes = 20_000_000
}
public enum FilterDecision: Equatable, Sendable {
    case accept
    case reject(Reason)
    public enum Reason: Sendable, Equatable { case ownWrite, paused, concealed, transient, autoGenerated, ignoredApp, oversized, empty }
}
public enum ClipFilter {
    /// `candidates` = every app that may have produced the copy (R82); rejection if any is ignored.
    public static func preflight(types: Set<String>, candidates: [SourceApp],
                                 settings: FilterSettings, ownBundleID: String, now: Date) -> FilterDecision
}
```

- R26. Preflight rules in order (first match wins): marker type present → `ownWrite`; `isPaused` and
  (`pausedUntil == nil` or `now < pausedUntil`) → `paused`; concealed or any `SensitiveTypes.all` member →
  `concealed`; transient → `transient`; auto-generated → `autoGenerated`; any candidate bundle id ∈
  ignored or == `ownBundleID` → `ignoredApp`. Then `ClipReader` yields `oversized` / `empty` (R81).
- R27. Defaults: `ignoredBundleIDs = ["com.apple.keychainaccess", "com.apple.Passwords",
  "com.1password.1password", "com.agilebits.onepassword7"]`, text limit 1 MB (1,000,000 bytes UTF-8),
  image limit 20 MB (20,000,000 bytes), rich-rep limit 2 MB.

### 4.3 ClipboardWatcher

```swift
@MainActor public final class ClipboardWatcher {
    public init(pasteboard: PasteboardReading, settings: @escaping @MainActor () -> FilterSettings,
                frontmostApp: @escaping @MainActor () -> SourceApp?, ownBundleID: String,
                clock: @escaping @MainActor () -> Date = Date.init,
                sink: @escaping @MainActor (CapturedContent, SourceApp?, Date) -> Void)
    public func start(interval: Duration = .milliseconds(300))
    public func stop()
    public func poll()                               // one tick; public for tests
    public func appActivated(_ app: SourceApp)       // fed from didActivateApplicationNotification
    public var onCapture: (@MainActor () -> Void)?   // menu bar pulse
}
```

- R28. `start` runs a MainActor `Task` loop (`poll(); try await Task.sleep(for: interval,
  tolerance: .milliseconds(100))` until cancelled; `stop` cancels it) — no `Timer` closure isolation
  issues — and polls once immediately so the clipboard present at launch is captured.
- R29. `poll()`: update tick state (R82); if `changeCount == lastChangeCount` return. Otherwise set `lastChangeCount` first
  (always — so content copied while paused/ignored is never captured later). Run preflight (R26) with
  candidates per R82; then `ClipReader.read` (R81); then `ClipExtractor.extract`; if non-nil call `sink`
  and `onCapture`. Attributed source = `declaredSource` (if a running app has that bundle id, use its
  localizedName) else `frontmostApp()`; if that is Clipjar itself, source = `nil`. Rejections are logged
  with the reason only (R67).
- R82. **Conservative attribution (D2).** The watcher keeps `frontmostAtLastTick` and `activatedSinceTick`
  (apps reported via `appActivated` since the previous tick). On **every** tick — including the
  no-change early return in R29 — the watcher first computes candidates, then sets
  `frontmostAtLastTick = frontmostNow` and clears `activatedSinceTick` (N4). Preflight
  candidates = `[declaredSource-app?, frontmostAtLastTick, …activatedSinceTick, frontmostNow]`; if **any**
  is ignored the clip is rejected, so copying in an ignored app and ⌘⇥-ing away within one tick is still
  rejected.
- R30. The app's `sink` yields into a single `AsyncStream<(CapturedContent, SourceApp?, Date)>`
  (`.unbounded`) consumed by one long-lived `Task` that awaits `store.ingest(...)` sequentially —
  preserving copy order. The stream is created before the store opens; captures made before the store is
  ready are buffered and ingested once the consumer starts (R86).

### 4.4 ClipStore

```swift
public enum HistoryLimit: Int, Sendable, CaseIterable { case l200 = 200, l1000 = 1000, l5000 = 5000, l10000 = 10000, unlimited = 0 }
public struct CapturedContent: Sendable, Equatable { kind, plainText, rtf, html, image: ImageData?, fileURLs: [URL], width, height }
public enum IngestResult: Sendable, Equatable { case inserted(Int64), bumped(Int64) }

public actor ClipStore {
    public init(writer: any DatabaseWriter, blobsDirectory: URL) throws   // runs migrator
    public nonisolated let reader: any DatabaseReader
    public nonisolated let blobsDirectory: URL

    @discardableResult
    public func ingest(_ c: CapturedContent, source: SourceApp?, at now: Date) throws -> IngestResult
    public func touch(id: Int64, at now: Date) throws                 // lastCopiedAt = now
    public func setPinned(id: Int64, _ pinned: Bool) throws
    public func delete(id: Int64) throws
    @discardableResult public func delete(id: Int64, ifLastCopiedAt: Date) throws -> Bool  // R87
    public func scrubIfPending() throws                                                   // R83
    public func clearAll(keepPinned: Bool) throws -> Int
    public func configure(limit: HistoryLimit, maxAgeDays: Int)
    public func prune(limit: HistoryLimit, maxAgeDays: Int, now: Date) throws -> Int
    public func pruneCount(limit: HistoryLimit, maxAgeDays: Int, now: Date) throws -> Int   // read-only
    public func cleanOrphanBlobs(now: Date, graceSeconds: TimeInterval = 60) throws -> Int
    public func payload(id: Int64) throws -> ClipPayload?
    public func clip(id: Int64) throws -> Clip?

    public nonisolated func rowsObservation(_ q: ClipQuery) -> ValueObservation<ValueReducers.Fetch<[ClipRow]>>
    public nonisolated func countObservation(_ q: ClipQuery) -> ValueObservation<ValueReducers.Fetch<Int>>
    public nonisolated func clipObservation(id: Int64) -> ValueObservation<ValueReducers.Fetch<Clip?>>
}
```

- R31. `ingest`: compute hash (R17) and, for images, thumbnail data inside the actor. For images, write
  any blob/thumbnail file that does **not already exist** (recording which ones this call created).
  Then **one** `writer.write {}` transaction does lookup-by-hash + bump (R19) or insert — never a separate
  read-then-write. If the transaction throws, delete only the files this ingest newly created and rethrow.
  After commit, call `prune` with the actor's config (`configure`, defaults `.l1000`, `0`); prune errors are
  caught and logged — the ingest still returns `.inserted`/`.bumped`.
- R32. **Pruning** (one write transaction, then file deletion after commit):
  1. If `maxAgeDays > 0`: select unpinned rows with `lastCopiedAt < now − maxAgeDays·86400`.
  2. If `limit != .unlimited`: select unpinned rows not in the newest `limit` unpinned rows ordered by
     `lastCopiedAt DESC, id DESC`. **Pinned clips never count toward the limit and are never pruned.**
  3. Collect `imagePath`/`thumbnailPath` of the union, `DELETE` those ids, commit, then remove the files
     (errors removing files are logged and ignored — orphan cleanup catches them).
  Prune also runs at launch, whenever limit/max-age settings change (after confirmation, R89), on every
  panel open, and on `NSWorkspace.didWakeNotification`. On panel open, `prepareForOpen` awaits the prune
  before (re)starting the rows observation, so the list for that open is rendered from post-prune data
  (N6); the panel chrome appears immediately.
- R33. `delete(id:)` and `clearAll(keepPinned: true)` follow the same "delete rows, commit, then remove
  blob files" order. `clearAll` is only exposed to the UI with `keepPinned: true`.
- R83. **Secure deletion (D8, N1).** `Configuration.prepareDatabase` runs `PRAGMA secure_delete = ON`.
  *User deletions* (committed ⌘⌫, `clearAll`) are scrubbed immediately: `INSERT INTO clip_fts(clip_fts)
  VALUES('optimize')` (after `clearAll`: `'rebuild'`), then `PRAGMA wal_checkpoint(TRUNCATE)` outside the
  transaction. *Prune deletions* only run the incremental `INSERT INTO clip_fts(clip_fts, rank)
  VALUES('merge', 16)` and set `scrubPending = true`; a deferred `optimize` + TRUNCATE checkpoint runs
  when `scrubPending` and ≥ 1 h since the last scrub (checked after each prune) and in
  `applicationWillTerminate` (`store.scrubIfPending()`). Guarantee: user-deleted text is gone from
  `clips.sqlite*` bytes immediately; pruned text within ~1 h.
- R34. **Orphan cleanup** runs once at launch (after open, off main): list `blobs/`, delete any file whose
  name is not referenced by any row's `imagePath`/`thumbnailPath` **and** whose modification date is older
  than `graceSeconds` (avoids racing an in-flight ingest). Also deletes stray `*.tmp` atomic-write leftovers.
- R35. **Opening and corruption recovery** (`StoreOpener.open(supportDirectory:) async -> OpenResult`,
  `OpenResult { store: ClipStore; recoveredFromCorruption: Bool }`):
  1. Create dirs/files (R22). Open `DatabasePool` (WAL) with `Configuration().busyMode = .timeout(5)`
     and `prepareDatabase` per R83. Run the migrator.
  2. If opening or migrating throws `.SQLITE_CORRUPT`/`.SQLITE_NOTADB` → move-aside (step 4).
  3. If the `needsRepair` flag file `<support>/.needs-repair` exists (written by R84): run
     `INSERT INTO clip_fts(clip_fts) VALUES('integrity-check')`; on error `'rebuild'`; then `REINDEX`;
     then full `PRAGMA integrity_check`. `"ok"` → delete the flag, continue (`recoveredFromCorruption =
     false`). Otherwise → move-aside. Plain launches (no flag) skip all checks (fast launch-at-login).
  4. *Move-aside:* close the pool; rename `clips.sqlite`, `-wal`, `-shm` to
     `clips.sqlite.corrupt-<yyyyMMdd-HHmmss>(-wal|-shm)` and `blobs/` to `blobs.corrupt-<same stamp>`
     (if the stamp exists, append `-2`, `-3`, …); open a fresh store; `recoveredFromCorruption = true`.
     Nothing is ever deleted; the banner says the old copy is kept (and may be removed manually).
  5. Any other error, or a failed rename / failed fresh open → **in-memory** `DatabaseQueue` + blobs dir
     under `FileManager.temporaryDirectory/Clipjar-<uuid>` (`0700`), `storageUnavailable` banner (§8).
- R84. **Runtime corruption (D7).** Any `DatabaseError` with `.SQLITE_CORRUPT` (incl. `_VTAB`) from a
  store call creates `<support>/.needs-repair` (empty, `0600`) and emits `StoreEvent.corrupt` → banner
  "…Restart Clipjar to repair." Repair happens at next launch per R35 step 3.
- R85. **Single instance (D1).** At launch, before opening the store, `InstanceLock.acquire(supportDir)`
  takes `flock(fd, LOCK_EX | LOCK_NB)` on `<support>/.lock` (held for process lifetime) and returns
  `.acquired`, `.heldByOther` (**only** when `flock` fails with `EWOULDBLOCK`), or `.failed(errno)` (any
  other dir/open/lock failure). `.heldByOther`: as a `.app` bundle, post `DistributedNotificationCenter`
  notification `"com.vtrifonov.clipjar.show"` (the running instance opens its panel centred) and
  `exit(0)`; otherwise (`swift run`, tests) continue with the in-memory store. `.failed`: log the errno,
  skip `StoreOpener`, continue with the in-memory store + `storageUnavailable` banner (never exit). The app also holds
  `ProcessInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Clipboard capture")`
  while capture is not paused (with R12's `NSAppSleepDisabled`).
- R36. `ClipQuery` → SQL. `ClipQuery { terms: [String]; apps: [String]; kinds: Set<ClipKind>?;
  pinnedOnly: Bool; limit: Int }`. WHERE clauses ANDed:
  - each term ≥ 3 characters: collected into one FTS MATCH `id IN (SELECT rowid FROM clip_fts WHERE
    clip_fts MATCH ?)`, match string = terms each wrapped in double quotes (inner `"` doubled) joined by
    ` AND `;
  - each term < 3 characters: `searchText LIKE ? ESCAPE '\'` with `%term%` (escape `%`, `_`, `\`);
  - all terms are folded per R80 first;
  - apps (OR among them): `(sourceAppName LIKE ? OR sourceBundleID LIKE ?)` with `%app%`;
  - `kinds` non-nil: `kind IN (…)` (empty set → query returns no rows without hitting the DB);
  - `pinnedOnly`: `isPinned = 1`.
  Order `lastCopiedAt DESC, id DESC`, `LIMIT limit`. Rows are selected with the `ClipRow` columns only.
  *(spec decision)* Pinned clips are **not** floated to the top; ordering is pure recency so ⌘1 is
  always "most recent". Pins are reached via the Pinned chip / `is:pinned`.

### 4.5 Paster

```swift
@MainActor public protocol AccessibilityChecking { func isTrusted() -> Bool }        // AXIsProcessTrusted()
@MainActor public protocol KeyEventPosting { func postCommandV() }                  // CGEvent
public struct SourceAppHandle: Sendable, Equatable { public var bundleID: String?; public var pid: pid_t }
@MainActor public protocol AppActivating {
    func activate(_ app: SourceAppHandle) -> Bool   // false if the process is no longer running
    func frontmostPID() -> pid_t?
    func beep()
}
public enum PasteOutcome: Equatable, Sendable { case pasted, copiedOnly(CopyReason)
    public enum CopyReason: Sendable { case userRequested, pasteDisabled, notTrusted, targetUnavailable } }

@MainActor public final class Paster {
    public init(store: ClipStore, pasteboard: PasteboardWriting, ax: AccessibilityChecking,
                keys: KeyEventPosting, apps: AppActivating, sleep: @escaping @Sendable (Duration) async -> Void)
    /// `closePanel` orders the panel out immediately (no fade) and returns once it is no longer key.
    public func perform(clipID: Int64, target: SourceAppHandle?, copyOnly: Bool,
                        pasteOnSelect: Bool, closePanel: @MainActor () async -> Void) async -> PasteOutcome
}
```

- R37. Exact sequence of `perform`:
  1. `payload = try await store.payload(id:)`; if `nil` or it throws (deleted meanwhile, blob missing)
     → `apps.beep()`, return `.copiedOnly(.userRequested)` without writing anything.
  2. `pasteboard.write(payload)` (includes marker → watcher ignores it, R26).
  3. `await closePanel()` — immediately after the write, always.
  4. `Task { try? await store.touch(id:, at: now) }` — **not awaited**; errors logged and ignored.
  5. Decide mode: `copyOnly` → `.userRequested`; `!pasteOnSelect` → `.pasteDisabled`;
     `!ax.isTrusted()` → `.notTrusted`; `target == nil` → `.targetUnavailable`. Copy-only: done
     (a `.notTrusted` outcome means the Accessibility banner shows on next open, R47).
  6. `apps.activate(target)`; `false` → `.targetUnavailable`, done. Poll `frontmostPID() == target.pid`
     every 10 ms for up to 250 ms. **Timeout → `.targetUnavailable`, never post ⌘V** (log a warning).
  7. `sleep(.milliseconds(40))`, re-check `frontmostPID() == target.pid` (else `.targetUnavailable`), then
     `keys.postCommandV()` exactly once → `.pasted`.
  ⌘V is therefore only ever posted after the panel has been ordered out and resigned key, into the
  verified target app.
- R38. `postCommandV`: `CGEventSource(stateID: .combinedSessionState)`; key down then key up for
  virtual key `0x09` (kVK_ANSI_V) with `flags = .maskCommand`; post both to `.cghidEventTap`.
- R39. `target` is captured by `PanelController` at open time as `NSWorkspace.shared.frontmostApplication`
  (ignored if it is Clipjar itself) and converted to a `SourceAppHandle`. The system `AppActivating`
  implementation resolves `NSRunningApplication(processIdentifier:)` and calls
  `activate(from: NSRunningApplication.current, options: [])` when Clipjar is the active app (cooperative
  activation, macOS 14+), else `activate(options: [])`; `beep()` = `NSSound.beep()`.

### 4.6 HotkeyController (Clipjar target)

- R40. `extension KeyboardShortcuts.Name { static let togglePanel = Self("togglePanel", initial: .init(.v, modifiers: [.command, .shift])) }`.
  `HotkeyController.init(onTrigger:)` registers `KeyboardShortcuts.onKeyDown(for: .togglePanel)`.
  Trigger toggles the panel (open near cursor; close if already open).
- R41. Persistence is KeyboardShortcuts' own `UserDefaults` storage (key `KeyboardShortcuts_togglePanel`),
  which survives restarts and app replacement (same bundle id). Clearing the recorder sets `nil`
  → no global hotkey; the panel stays reachable from the menu bar, and the header hotkey hint is
  hidden *(spec decision)*.
- R42. Conflict detection: the Settings form applies
  `.keyboardShortcutsConflictPolicy(.init(menuItem: .block, systemShortcut: .block))` (the library default
  only *warns* on system shortcuts and offers "Use Anyway"), and the recorder is
  `Recorder(for: .togglePanel, validateShortcut:)` returning `.disallow("Use at least one of ⌘, ⌥ or ⌃.")`
  for shortcuts without ⌘/⌥/⌃. Blocked/disallowed shortcuts are never stored; the previous value stays.

### 4.7 PanelController (Clipjar target)

- R43. `ClipjarPanel: NSPanel`, created once at launch and reused (keeps open latency < 50 ms):
  `styleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]`, `canBecomeKey = true`
  (override), `canBecomeMain = false`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces,
  .fullScreenAuxiliary, .transient, .ignoresCycle]`, `isOpaque = false`, `backgroundColor = .clear`,
  `hasShadow = true`, `hidesOnDeactivate = false`, `isMovable = false`, `animationBehavior = .none`,
  `isReleasedWhenClosed = false`. Content: `NSHostingView(rootView: HistoryView(model:))`.
- R44. Size 720 × 460 pt. Positioning (`PanelPlacement`, pure function in ClipjarCore, unit-tested):
  - **From status item:** centre horizontally on the status button's screen frame; top edge 6 pt below
    the button's bottom.
  - **From hotkey:** screen = the `NSScreen` whose frame contains `NSEvent.mouseLocation` (fallback
    `.main`). Centre horizontally on the cursor; top edge 16 pt below the cursor; if that doesn't fit,
    bottom edge 16 pt above the cursor.
  - Both: clamp the frame inside that screen's `visibleFrame` inset by 8 pt.
  - **Centred** (reopen / first run / second-instance, R86): centred in the main screen's `visibleFrame`,
    vertically at 1/3 from the top.
- R45. Show: record target app (R39), reset view model (`model.prepareForOpen()`: query = "", filter =
  All, select first row, scroll to top, re-evaluate banners, trigger prune R32), `makeKeyAndOrderFront(nil)`,
  focus search field, run open animation (R55). Must not call `NSApp.activate`.
- R46. Dismiss on: Esc with empty query; hotkey or status click while open; `windowDidResignKey`;
  a global `NSEvent` monitor for `.leftMouseDown/.rightMouseDown` outside the panel frame (installed
  on show, removed on hide); after a paste/copy. Normal hide = close animation then `orderOut`; the
  **paste/copy path** uses `hideImmediately() async` = `orderOut` with no fade, then awaits until
  `panel.isKeyWindow == false` (Paster R37 step 3). Hiding commits any pending deletion (R87). If Clipjar
  became the active app while open (e.g. Settings was opened), re-activate the recorded target on hide.
  Opening Settings from the gear closes the panel first.

### 4.8 HistoryViewModel (ClipjarCore, `@MainActor @Observable`)

```swift
public enum FilterChip: CaseIterable, Sendable { case all, text, links, images, files, pinned }
public enum PanelCommand: Equatable, Sendable {
    case moveUp, moveDown, moveToTop, moveToBottom, pageUp, pageDown
    case activate(copyOnly: Bool), activateRow(Int /*1...9*/), togglePin, delete, undoDelete
    case nextFilter, previousFilter, escape, close, openSettings
}
public enum Banner: Equatable, Sendable { case accessibility, pasteboardDenied, appTranslocated,
    recoveredFromCorruption, storageUnavailable, storageError, storageCorrupt }
public enum Toast: Equatable, Sendable { case deleted(Int64), confirmPinnedDelete(Int64) }

@MainActor @Observable public final class HistoryViewModel {
    public var query: String { didSet }      // re-subscribes observation
    public var filter: FilterChip
    public private(set) var rows: [ClipRow]
    public private(set) var selectedID: Int64?
    public private(set) var selectedClip: Clip?   // full clip for preview, observed by id
    public private(set) var matchCount: Int  // current query + chip; shown in chip-bar label (R57)
    public private(set) var allCount: Int    // unfiltered: countObservation(.all)
    public private(set) var banners: [Banner]
    public private(set) var toast: Toast?
    public private(set) var highlightTerms: [String]
    public var isEmptyHistory: Bool          // allCount == 0 (ignoring pending deletion)
    public var isNoResults: Bool             // rows empty && !isEmptyHistory
    public init(store: ClipStore, actions: HistoryActions, clock: @escaping () -> Date = Date.init)
    public func handle(_ cmd: PanelCommand) -> Bool          // true = consumed
    public func hover(id: Int64, mouseLocation: CGPoint)      // ignored unless the mouse really moved
    public func rowAppeared(index: Int)                       // paging trigger
    public func prepareForOpen()
}
```

- R48. **Observation:** a `Task` iterates `store.rowsObservation(q).values(in: store.reader)`; changing
  `query`/`filter`/`limit` cancels the task and starts a new one. Page size 100; when
  `rowAppeared(index) >= rows.count - 15` and `fetchedCount == limit`, `limit += 100` (`fetchedCount` =
  rows returned by the store **before** the pending-deletion filter, A24).
- R49. **Query parser** (`QueryParser.parse(_:) -> ParsedQuery`, pure): split on whitespace, honouring
  `"double quoted phrases"` as one term. Token `@x` (x non-empty) → app filter `x` (multiple → OR).
  `is:link|image|file|text` → kind (multiple → OR); `is:pinned` → pinnedOnly. Case-insensitive keywords.
  A bare `@` or `is:` or unknown `is:foo` → treated as a literal term *(spec decision: bare `@`/`is:` are
  ignored, unknown `is:foo` is literal)*. Remaining tokens are terms. Combined with the chip:
  chip kind ∩ token kinds (empty intersection → no results); chip Pinned ⇒ pinnedOnly.
  Chip → kinds: All = nil, Text = {text}, Links = {link}, Images = {image}, Files = {file}.
- R50. **Selection rules:**
  - When query or filter changes: select the first row (or `nil` when empty).
  - When rows change for the same query (DB update): keep `selectedID` if still present; else select
    the row now at the previous index, clamped to `rows.count - 1`; else `nil`.
  - After `delete`: select the row that takes the deleted index; if it was last, the new last row.
  - `moveUp` at index 0 and `moveDown` at last index are no-ops (no wrap). `pageUp/Down` move by 8.
  - `hover(id:mouseLocation:)` sets selection only if `mouseLocation` (the view passes
    `NSEvent.mouseLocation`) differs from the last recorded one **and** ≥ 150 ms have passed since the last
    keyboard move (keyboard `scrollTo` under a still cursor must not steal selection).
  - `selectedClip` is fetched via `clipObservation(id:)` and updated within one runloop of selection.
- R51. **Commands:** `activate(copyOnly)` → `actions.paste(selectedID, copyOnly)`; no selection →
  beep, not consumed. `activateRow(n)` → row `n-1` if it exists, else beep. `togglePin` acts on the
  selection via the store; `delete` per R87. `nextFilter/previousFilter` cycle All→Text→Links→Images→
  Files→Pinned (wrapping). `escape`: toast visible → dismiss toast (commits); non-empty query → clear
  query; else `actions.close()`. `openSettings` → `actions.openSettings()`.
- R87. **Undoable delete (A1).** `delete` on an unpinned clip: commit any previous pending deletion, set
  `pendingDeletionID`, hide that row from `rows` (VM-side filter; selection per R50), show toast
  `.deleted` "Clip deleted · Undo ⌘Z" for 5 s. `undoDelete` (⌘Z, only while that toast is visible)
  clears the pending id; the row reappears with its selection restored. The store commit runs when the
  toast expires, the panel hides, the next delete starts, or the app terminates (R86), as
  `store.delete(id:ifLastCopiedAt:)` = `DELETE FROM clip WHERE id = ? AND lastCopiedAt = ?` with the
  value recorded at ⌘⌫ time (N3): if the same content was re-copied during the undo window (bumped), no row
  is deleted, the pending id is cleared and the row reappears. **Pinned clip:** first ⌘⌫ only shows toast
  `.confirmPinnedDelete` "Pinned — press ⌘⌫ again to delete" (2 s); a second ⌘⌫ on the same clip within
  2 s proceeds as above.
- R52. Highlighting: `Highlighter.ranges(of: terms, in: text) -> [Range<String.Index>]`, case- and
  diacritic-insensitive, non-overlapping, max 50 ranges.

### 4.9 SettingsStore (ClipjarCore, `@MainActor @Observable`)

- R53. Backed by an injectable `UserDefaults` (tests use `UserDefaults(suiteName: UUID().uuidString)`).

| Key | Type | Default | Notes |
|---|---|---|---|
| `historyLimit` | Int | `1000` | one of 200, 1000, 5000, 10000, 0 (=unlimited) |
| `maxAgeDays` | Int | `0` (off) | one of 0, 1, 7, 30, 90, 365 |
| `ignoredBundleIDs` | [String] | 4 defaults (R27) | user can remove defaults |
| `hasLaunchedBefore` | Bool | `false` | first-run panel (R86) |
| `isPaused` | Bool | `false` | |
| `pausedUntil` | Double? | `nil` | `timeIntervalSince1970`; nil + `isPaused` = indefinite |
| `pasteOnSelect` | Bool | `true` | off ⇒ ⏎ copies only |
| `KeyboardShortcuts_togglePanel` | — | ⇧⌘V | owned by KeyboardShortcuts |

  Launch at login is **not** stored; it is read from `SMAppService.mainApp.status` each time Settings opens.
  Pause persists across restarts; an expired timed pause is cleared on read. `filterSettings` returns a
  `FilterSettings` snapshot. Changing limit/max-age goes through R89.
- R88. **Pause expiry (A7).** `SettingsStore(defaults:clock:scheduler:)` — `scheduler` is an injectable
  `(Date, @escaping @MainActor () -> Void) -> Cancellable` (production: one-shot `Timer` on the main run
  loop, `.common` mode). Setting a timed pause schedules a fire at `pausedUntil` that clears `isPaused` /
  `pausedUntil`, so every observer (menu bar dimming, menu title, Settings toggle, panel bar) updates.
  Re-armed at launch from the persisted value; cancelled on Resume or a new pause.
- R89. **Destructive setting changes (A8).** Before applying a new limit/max-age, Settings calls
  `store.pruneCount(limit:maxAgeDays:now:)`. N = 0 → apply (`configure` + `prune`). N > 0 →
  `confirmationDialog` "Remove N older clips? Pinned clips are kept." [Remove] [Cancel]; Cancel reverts
  the picker to the previous value and nothing is pruned.

### 4.10 App lifecycle (Clipjar target)

- R86. `applicationDidFinishLaunching` order: (1) hidden main menu (R91); (2) `InstanceLock.acquire`
  (R85, may exit); (3) `SettingsStore` + pause timer (R88); (4) capture `AsyncStream` + start watcher
  (R28; captures buffer until 6); (5) status item (R61), `HotkeyController` (R40), observers for
  `didActivateApplication` (→ `watcher.appActivated`, R82), `didWake` (→ prune) and distributed
  `"com.vtrifonov.clipjar.show"` (→ panel centred); (6) `await StoreOpener.open` → `configure` → `prune`
  → start ingest consumer (R30) → detached `cleanOrphanBlobs`; (7) panel + view model with `OpenResult`
  banners. Open triggers (hotkey, status click, reopen, show notification) arriving before step 7 — which
  can take seconds during an R35 repair — are coalesced into **one** queued open request (keeping the
  latest placement) and performed right after step 7 (A27); (8) if `!hasLaunchedBefore`, set it and
  open the panel centred. `applicationWillTerminate` (A25): commit any pending deletion (R87), then
  `store.scrubIfPending()` (R83), waiting at most 2 s (semaphore-bounded `Task`). Runtime store errors reach the UI through `StoreEvents`, a MainActor
  `(StoreEvent) -> Void` (`.writeFailed`, `.corrupt`) wired into the ingest consumer and the view
  model's store calls → `storageError`/`storageCorrupt` banners. `applicationShouldHandleReopen` → open
  the panel centred, return `false`.
- R91. **Hidden main menu (A3).** `NSApp.mainMenu` is built in code (never visible for an LSUIElement app,
  but key equivalents route through it): App menu (About Clipjar, Settings… ⌘,, Quit Clipjar ⌘Q); Edit
  (Undo ⌘Z, Redo ⇧⌘Z, Cut, Copy, Paste, Select All with standard selectors); Window (Close ⌘W →
  `performClose:`). This makes ⌘A/⌘C/⌘V/⌘X/⌘Z work in the search field and Settings, and makes
  KeyboardShortcuts block ⌘V/⌘C as the global hotkey. **Own copies carry the marker (N5):** Edit ▸ Copy
  and Cut target Clipjar's `ClipjarEditActions` (`clipjarCopy:`/`clipjarCut:`), which forward
  `copy:`/`cut:` to the key window's first responder (`NSApp.sendAction(_:to: nil, from:)`) and, if
  `NSPasteboard.general.changeCount` advanced, add `PasteboardTypes.marker` (empty data) to the first
  item — so text copied from Clipjar's search field or preview is not captured and never attributed to
  the target app.
- R92. **Pasteboard access (A6).** At launch and on each panel open, `if #available(macOS 15.4, *)` read
  `NSPasteboard.general.accessBehavior`; `.alwaysDeny` → `pasteboardDenied` banner "Clipjar can't read
  your clipboard. Allow it in System Settings ▸ Privacy & Security." + **Open Settings**
  (`x-apple.systempreferences:com.apple.preference.security`).
- R93. **App Translocation (A22).** If `Bundle.main.bundlePath` contains `/AppTranslocation/`, show the
  `appTranslocated` banner "Move Clipjar to the Applications folder so permissions stick." (not
  dismissible).

---

## 5. Concurrency model (Swift 6 strict)

- R54.
  - **@MainActor:** everything AppKit/SwiftUI-facing — `SystemPasteboard`, `ClipboardWatcher`, `Paster`,
    `HistoryViewModel`, `SettingsStore`, `PanelController`, `StatusItemController`, `HotkeyController`,
    `AppDelegate`, all views (`Clipjar` target has MainActor default isolation).
  - **actor `ClipStore`:** all writes, hashing, thumbnailing, blob file IO run on its executor — never on
    main. Its `reader`/`blobsDirectory`/observation builders are `nonisolated` (GRDB readers are `Sendable`).
  - **Sendable values:** `Clip`, `ClipRow`, `ClipKind`, `CapturedContent`, `ClipPayload`,
    `PasteboardSnapshot`, `FilterSettings`, `ClipQuery`, `ParsedQuery`, `SourceApp`, `HistoryLimit`.
  - **Pure enums/functions** (`ClipFilter`, `ClipExtractor`, `QueryParser`, `TextHeuristics`,
    `Highlighter`, `PanelPlacement`) are nonisolated.
- Main-thread pasteboard work: `types()` every tick, plus — for accepted clips only — the single chosen
  representation (R81). NSPasteboard offers no size query, so that read can be up to the limit (20 MB);
  this is an accepted, documented cost. DB reads for the UI happen in GRDB's reader pool via
  `ValueObservation.values(in:)`; results are awaited by MainActor tasks. No `@unchecked Sendable`, no
  `nonisolated(unsafe)`, no `DispatchQueue.main.sync`.
- R90. **Off-main image/file IO (A13, M4).** Row thumbnails and the preview image are decoded off-main in a
  `Task.detached` via `CGImageSourceCreateThumbnailAtIndex` (rows: the stored thumb; preview: max pixel
  size = pane size × backing scale), returning a `CGImage` wrapped into `NSImage` on main; results cached
  in a MainActor `NSCache` (limit 300). The preview task is cancelled when selection changes; the row
  thumbnail is shown as placeholder meanwhile. File-clip stats (`URLResourceValues`, existence, workspace
  icon) are likewise fetched off-main and cancelled on selection change. App icons via
  `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` + `icon(forFile:)`, cached by bundle id.

---

## 6. UI / UX specification

Fonts use SwiftUI text styles (so they scale where macOS allows); nominal sizes at default setting are
given in parentheses. Colours are semantic (`.primary`, `.secondary`, `.tertiary`, `Color.accentColor`)
so light/dark and the user's accent colour work automatically.

### 6.1 Panel anatomy (720 × 460 pt)

```
┌───────────────────────────────────────────────────────────────────────────┐
│ 🔍 Search clips…                                         [⇧⌘V]   ⚙︎     │ header 52
├───────────────────────────────────────────────────────────────────────────┤
│ ⚠︎ banner (optional, 36)                                                   │
│ (All) Text  Links  Images  Files │ Pinned                      1,204 clips │ chips 36
├──────────────────────────────┬────────────────────────────────────────────┤
│ list (300 wide)              │ preview (fills)                             │ body
├──────────────────────────────┴────────────────────────────────────────────┤
│ ⏎ Paste   ⌥⏎ Copy   ⌘P Pin   ⌘⌫ Delete   ⇥ Filter                         │ footer 28
└───────────────────────────────────────────────────────────────────────────┘
```

- R55. **Chrome:** `NSVisualEffectView` material `.popover`, blending `.behindWindow`, state `.active`,
  clipped to a 12 pt continuous rounded rect; 0.5 pt inner stroke `Color.primary.opacity(0.08)`
  (Increase Contrast: 1 pt `Color(nsColor: .separatorColor)` and material swapped for
  `.windowBackground`-coloured opaque fill). System window shadow (`hasShadow`).
- R56. **Header (52 pt, horizontal padding 14):** `magnifyingglass` (15 pt, `.secondary`), 8 pt gap,
  plain `TextField` font `.title3` (15 pt), placeholder "Search clips…", focused on open. Trailing:
  hotkey hint capsule (current shortcut description, `.caption` medium, `.secondary`, padding 6×2,
  `RoundedRectangle(5)` fill `.quaternary`; hidden if no hotkey), 8 pt, gear button 28×28 borderless
  `gearshape` 14 pt, help tooltip "Settings (⌘,)". 1 px divider below.
- R57. **Filter chips (36 pt, horizontal padding 12, spacing 6):** All (`tray.full`), Text
  (`text.alignleft`), Links (`link`), Images (`photo`), Files (`doc`), 1 pt vertical separator 14 tall,
  Pinned (`pin`). Chip = icon 11 pt + label `.callout` medium (12 pt), padding 10×4, `Capsule`.
  Selected: fill `accentColor.opacity(0.18)`, foreground `accentColor`. Unselected: `.secondary`; hover
  fill `.quaternary`. Trailing count label `.caption` `.tertiary` showing `matchCount` ("1 clip"/"1,204
  clips", locale-grouped).
- R58. **List (300 pt wide):** `ScrollViewReader` + `ScrollView` + `LazyVStack(spacing: 2)` with 6 pt
  outer inset (not `List`, for pill styling and hover control). Selected row auto-scrolls into view
  (`scrollTo(id, anchor: nil)`) on keyboard moves only.
  **Row** (min height 44, padding 8×6, `HStack(spacing: 10)`):
  - leading 20×20: source app icon (fallback SF `app.dashed`, `.tertiary`);
  - for images a 28×28 thumbnail (4 pt radius, 0.5 pt hairline) replaces the app icon and the app icon
    moves into line 2 at 12×12;
  - line 1: `previewText`, one line, tail truncation, `.body` (13 pt), SF Mono `.body.monospaced()` if
    code-like (R21); match ranges bold + `accentColor`; hex colours prefixed by a 12×12 swatch
    (3 pt radius, 0.5 pt `.primary.opacity(0.2)` border); links show line 1 = the URL with the domain
    portion in `.primary` and the rest `.secondary`;
  - line 2 `.caption` (10 pt) `.secondary`: `[domain · ]AppName · relative time` (relative via
    `RelativeDateTimeFormatter`, `.short` (e.g. "2 min. ago"; `.abbreviated` renders "2m ago" on macOS 26),
    refreshed every 60 s while open; "now" < 60 s);
    files: "3 files · Finder · 2 min. ago";
  - trailing: `pin.fill` 10 pt `.secondary` if pinned; `⌘1`…`⌘9` in `.caption2` monospaced `.tertiary`
    for the first 9 rows.
  - **Selection pill:** `RoundedRectangle(8, style: .continuous)` fill `accentColor.opacity(0.22)`
    (Increase Contrast: 0.35 plus 1 pt `accentColor` stroke); shared via `matchedGeometryEffect` so it
    glides between rows (`.spring(response: 0.22, dampingFraction: 0.9)`); text stays `.primary`.
- R59. **Preview pane (padding 16):** header line `.caption` `.secondary`: kind icon + summary
  (text: "Text · 1,204 characters · 37 lines"; link: "Link · example.com"; image: "Image · 1200 × 800 px ·
  245 KB"; files: "3 files"), second line "Copied from Safari · Today at 14:32" (absolute, `.caption`
  `.tertiary`), pinned badge if pinned. 12 pt gap, then content:
  - text/link: `ScrollView` with `Text` in `.body.monospaced()` (12 pt), `textSelection(.enabled)`,
    highlights applied; renders at most the first 20,000 characters then a `.caption` footer
    "Showing first 20,000 of 154,203 characters";
  - image: decoded off-main at pane size (R90; thumbnail as placeholder), aspect-fit, 6 pt radius,
    hairline, never upscaled beyond 1× pixel size;
  - files: per file (max 20, then "+N more"): 32 pt workspace icon, name `.headline`, path `.caption`
    monospaced middle-truncated, size via `URLResourceValues.fileSize`/"Folder"; missing file →
    `exclamationmark.triangle` + "No longer exists" `.secondary`.
- R60. **Footer (28 pt, padding 12):** `.caption` `.tertiary` hints: "⏎ Paste  ⌥⏎ Copy  ⌘P Pin  ⌘⌫ Delete
  ⇥ Filter"; when paste-on-select is off or untrusted, "⏎ Copy" replaces "⏎ Paste  ⌥⏎ Copy". Pinned row
  selected → "⌘P Unpin".

### 6.2 States

- R47. **Banners** (36 pt, between header and chips, `RoundedRectangle(8)` inset 8, fill
  `Color.yellow.opacity(0.15)`, `exclamationmark.triangle.fill` yellow, text `.callout`):
  - Accessibility (when `pasteOnSelect` and `!AXIsProcessTrusted()`, re-evaluated on each open):
    "Allow Accessibility access so Clipjar can paste for you. Until then, ⏎ copies." Button
    **Open Settings** → opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
    and calls `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` once to register Clipjar
    in the list. Not dismissible (disappears once trusted).
  - Recovered: "Your clip history was damaged and has been reset. The old file was kept in the
    Clipjar support folder." Button **Show in Finder**; dismiss ✕ (shown until dismissed, once).
  - Storage unavailable: "History can't be saved to disk this session." dismiss ✕.
  - Storage error (runtime write failed): "Couldn't save the last clip." auto-hides after 6 s.
  - Storage corrupt (R84): "Clipjar's history database is damaged. Restart Clipjar to repair." dismiss ✕.
  - Pasteboard denied (R92) and App Translocation (R93): not dismissible.
- **Toast** (R87): floating capsule centred 12 pt above the footer, `.regularMaterial`, `.callout`,
  padding 12×6, fade 120 ms (instant under Reduce Motion); "Clip deleted · **Undo ⌘Z**" (button) or
  "Pinned — press ⌘⌫ again to delete". VoiceOver announces it (`AccessibilityNotification.Announcement`).
- **Empty history:** centred in body: `doc.on.clipboard` 36 pt `.tertiary`, "Your clipboard history is
  empty" `.title3`, "Copy something, then press ⇧⌘V to find it here." `.callout` `.secondary` (uses
  the actual shortcut; if none: "…then click the Clipjar icon in the menu bar.").
- **No results:** "No clips match “query”" + borderless button **Clear Search** (also Esc).
  If a chip other than All is active: second button **Search All Types**.
- **Paused:** thin bar above footer: `pause.circle` "Capture paused · Resumes at 14:47" (or
  "until you resume") + **Resume** button.

### 6.3 Keyboard map

Handled by a local `NSEvent` key-down monitor installed while the panel is key; mapped to `PanelCommand`
via `PanelKeyMap.command(for keyCode:, modifiers:, toastVisible:) -> PanelCommand?` (pure, tested).
Unmapped keys go to the search field. R94: the monitor returns the event untouched while the first
responder is an `NSTextView` with `hasMarkedText() == true` (IME composition: ⏎/↑/↓/⇥/Esc belong to the
input method). `PanelKeyMap` never claims ⌘A/⌘C/⌘V/⌘X, and claims ⌘Z only while the delete toast is
visible — otherwise these reach the field editor via the main menu (R91).

| Keys | Command | Notes |
|---|---|---|
| ↑ / ↓ | moveUp / moveDown | no wrap |
| ⌘↑ / ⌘↓ | moveToTop / moveToBottom | |
| Page Up / Page Down | pageUp / pageDown | 8 rows |
| ⏎ (also keypad Enter) | activate(copyOnly: false) | paste (or copy, see R37) |
| ⌥⏎ | activate(copyOnly: true) | copy only |
| ⌘1 … ⌘9 | activateRow(n) | paste row n |
| ⌥⌘1 … ⌥⌘9 | — | *(spec decision)* not mapped in v1 |
| ⌘P | togglePin | |
| ⌘⌫ | delete | undoable 5 s; pinned needs a second ⌘⌫ (R87) |
| ⌘Z | undoDelete | only while the delete toast is visible |
| ⇥ / ⇧⇥ | nextFilter / previousFilter | wraps |
| Esc | escape | clear query, else close |
| ⌘, | openSettings | |
| ⌘W | close | |
| ⌘Q | close | consumed while the panel is key, so it never quits Clipjar (A23); Quit lives in the status menu |

Mouse: hover selects (R50); click = activate; ⌥-click = copy only; right-click context menu on a row:
Paste, Copy, Pin/Unpin, Delete (with the same shortcuts displayed).

### 6.4 Motion

- R55a. Open: opacity 0→1 and scale 0.97→1 (anchor top) over 120 ms `easeOut`. Close: opacity →0 over
  80 ms, then `orderOut` (paste/copy path: no fade, R46). Selection glide spring as R58. Menu bar capture pulse: status button image
  alpha 1→0.35→1 over 300 ms. **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
  / `@Environment(\.accessibilityReduceMotion)`): all of the above become instant; no pulse.

### 6.5 Menu bar item

- R61. `NSStatusItem` (variable length) with SF Symbol `list.clipboard` as template image (16 pt,
  accessibility description "Clipjar"). Left click toggles panel (R44 status placement). Right-click or
  ⌃-click shows menu: "Open Clipjar" (shows shortcut), separator, "Pause for 15 Minutes", "Pause" /
  "Resume", separator, "Settings…" ⌘,, "Quit Clipjar" ⌘Q. While paused: `button.appearsDisabled = true`
  (dimmed) and tooltip "Clipjar — paused".

### 6.6 Settings window

- R62. `NSWindow` (titled, closable, 480 pt wide, height fits) hosting SwiftUI `Form` (`.formStyle(.grouped)`),
  title "Clipjar Settings"; opening it calls `NSApp.activate()` and centres the window once.
  Sections:
  - **General:** "Open Clipjar:" `KeyboardShortcuts.Recorder(for: .togglePanel)` + caption "Clear to use the
    menu bar icon only."; Toggle "Paste automatically after selecting" (`pasteOnSelect`) with caption
    linking to Accessibility status ("Accessibility: Allowed ✓" / "Not allowed — Open Settings");
    Toggle "Launch at login" (SMAppService; on `.requiresApproval` show caption + button
    "Open Login Items" → `SMAppService.openSystemSettingsLoginItems()`).
  - **History:** Picker "Keep" (200 / 1,000 / 5,000 / 10,000 / Unlimited clips); Picker "Remove clips
    older than" (Never / 1 day / 1 week / 30 days / 90 days / 1 year), both confirmed per R89; caption
    "Pinned clips are never removed."; Button "Clear History…" (destructive) → `confirmationDialog` "Clear all unpinned clips?
    This can't be undone." [Clear History] [Cancel].
  - **Privacy:** Toggle "Pause capture" + Button "Pause for 15 minutes"; list "Ignored apps" (icon +
    name + bundle id `.caption`; `−` removes selected), `+` opens `NSOpenPanel` at `/Applications`
    (`allowedContentTypes: [.applicationBundle]`, multiple) and adds each `Bundle(url:)?.bundleIdentifier`;
    caption "Clipjar also skips anything apps mark as concealed, such as passwords. History is stored
    unencrypted on this Mac and never leaves it."
  - Footer: version string "Clipjar 0.1.0 (1)" `.caption` `.tertiary`.

### 6.7 Accessibility

- R63. VoiceOver labels: search field "Search clips"; chip "Filter: Text, selected"; row label
  "<kind>, <preview first 100 chars>, from <App>, <relative time>[, pinned]" with hint "Press Return to
  paste" and custom actions Pin/Unpin, Delete, Copy; preview image "Image, W by H pixels"; colour swatch
  "Colour #RRGGBB"; gear "Settings"; status item "Clipjar"; banner buttons labelled by text.
  Selection changes post `NSAccessibility.Notification.selectedChildrenChanged` via the list being an
  accessibility container with `.isSelected` traits. All controls keyboard reachable in Settings.
  Increase Contrast handled per R55/R58; Dynamic Type via text styles.

---

## 7. Privacy & security

- R64. **Local only:** no networking code in our sources; CI fails if
  `rg -n 'URLSession|NSURLConnection|import Network|NWConnection|CFNetwork|CFStream|SCNetworkReachability|WebKit|\bsocket\(|\bconnect\(' Sources`
  matches. No
  analytics, no crash reporting, no update checks. No entitlements; app is not sandboxed (needed to post
  CGEvents and read other apps' pasteboard metadata freely).
- R65. Concealed/transient/auto-generated/legacy sensitive types, ignore list (with conservative
  attribution, R82), own writes and pause per R26 — all decided before any content is read (R81).
- R66. Files: support dir `0700`, DB & blobs `0600` (R22), excluded from Time Machine; deleted clips are
  scrubbed from disk (R83). Unencrypted at rest — stated in README and Settings (R62).
- R67. **Logging:** `os.Logger(subsystem: "com.vtrifonov.clipjar", category:)` with categories
  `capture`, `store`, `paste`, `panel`, `hotkey`. Log events, kinds, byte sizes, counts, durations,
  filter reasons and error codes. **Never** log clip content, preview text, file paths from clips, or
  content hashes (hashes of short secrets are brute-forceable). Errors are logged as domain + code
  (`DatabaseError.resultCode`, `CocoaError.Code`, errno) only — never `localizedDescription` or file paths
  (blob paths contain hashes). Source bundle ids only at `.debug` with `privacy: .private`.
- R68. Accessibility permission is used solely to post ⌘V. Clipjar never reads other apps' UI.

---

## 8. Error handling

| Failure | Behaviour |
|---|---|
| DB corrupt/not-a-db at launch | Move aside with timestamp, fresh DB, Recovered banner (R35) |
| DB can't be opened for other reasons, or move-aside fails | In-memory store this session, Storage-unavailable banner |
| Another Clipjar instance holds the lock (`EWOULDBLOCK`) | Signal it to show its panel, exit (`.app`); else in-memory (R85) |
| Lock file/dir can't be created or locked for any other reason | Log errno; in-memory store + Storage-unavailable banner; never exit (R85) |
| Write/ingest throws at runtime | Log error code; Storage-error banner (auto-hide 6 s); capture continues |
| Prune throws after a successful insert | Logged only; ingest reported as success (R31) |
| `SQLITE_CORRUPT` at runtime | `.needs-repair` flag + Storage-corrupt banner; next launch repairs FTS/indexes, moves aside only if table data is bad (R84, R35) |
| Blob write fails (disk full) | Ingest aborted, no row inserted, only newly created files removed, Storage-error banner |
| Image re-copied while its blob is missing | Bump rewrites blob/thumbnail (R19) |
| Pasteboard access denied (macOS 15.4+) | Pasteboard-denied banner (R92) |
| `touch` fails after paste | Logged, ignored (R37) |
| Blob missing when previewing/pasting image | Preview shows "Image unavailable"; paste beeps, nothing written |
| Thumbnail generation fails | Insert row without thumbnail; row shows `photo` symbol |
| Image undecodable | Not captured (R15) |
| File in a file clip no longer exists | Preview marks it; paste still writes the URLs (target app decides) |
| Payload `nil` on paste (deleted concurrently) | Beep, nothing written |
| Accessibility not granted | Copy-only + banner (R37, R47) |
| Target app quit / `nil` / activate refused | Copy-only (`.targetUnavailable`), no ⌘V posted |
| Target app not frontmost after 250 ms | Copy-only (`.targetUnavailable`), **no ⌘V posted**, log warning |
| Hotkey registration fails silently (held by another app) | Hint still shown; user can re-record; menu bar works |
| SMAppService register/unregister throws | Revert toggle, show caption with error description |
| NSOpenPanel item without bundle id | Skipped silently |
| Orphan-cleanup / blob delete fails | Logged, ignored |

---

## 9. Portability & distribution

- R69. Universal binary (R10/R11); `make app` fails if `lipo -archs` lacks either arch. No absolute
  paths, usernames or machine-specific values in sources, Makefile, workflows or README; all paths via
  `FileManager` APIs or Makefile variables.
- R70. **CI** `.github/workflows/ci.yml`: `on: [push, pull_request]`; job `build-test` `runs-on: macos-26`;
  workflow-level `env: XCODE_VERSION: "<pinned stable, e.g. 26.0>"` (bumped deliberately, never a beta);
  steps: checkout (`actions/checkout@v4`); `sudo xcode-select -s "/Applications/Xcode_${XCODE_VERSION}.app"`;
  `swift --version` (must be ≥ 6.2); no-network grep (R64); `make test`; `make app` (proves universal assembly);
  cache `.build` keyed on `Package.resolved`. `Package.resolved` is committed.
- R71. **Release** `.github/workflows/release.yml`: `on: push: tags: ['v*']`; `permissions: contents: write`;
  same runner and pinned `XCODE_VERSION`; `make zip VERSION=${GITHUB_REF_NAME#v} BUILD_NUMBER=${{ github.run_number }}`;
  `gh release create "$GITHUB_REF_NAME" build/Clipjar.zip --title "Clipjar $GITHUB_REF_NAME"
  --generate-notes` with `GH_TOKEN: ${{ github.token }}`.
- R72. **README** sections: what it is (+ screenshot), features, keyboard map, **Install** (download
  `Clipjar.zip` from Releases → unzip → move to Applications; first run: right-click ▸ **Open** ▸ **Open**,
  or on macOS 15+ System Settings ▸ Privacy & Security ▸ **Open Anyway**; alternative
  `xattr -dr com.apple.quarantine /Applications/Clipjar.app`; explain it's ad-hoc signed, not notarized;
  always move it to Applications before first launch — running from Downloads (App Translocation) breaks
  permissions), **Accessibility** (System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable Clipjar;
  after an update, toggling is not enough because ad-hoc signatures change per build: remove Clipjar with
  "−" and re-add it, or run `tccutil reset Accessibility com.vtrifonov.clipjar` and relaunch),
  **Clipboard access** (macOS 15.4+ may ask whether Clipjar may read the pasteboard — choose Always Allow;
  if denied, re-enable in Privacy & Security), build from source (`make test`, `make install`; requires
  Xcode with Swift ≥ 6.2), privacy statement (local-only, unencrypted, concealed types, ignore list,
  excluded from Time Machine, deleted clips scrubbed), data location
  (`~/Library/Application Support/Clipjar`; `*.corrupt-*` copies there may be deleted), uninstall (quit,
  delete app and that folder), licence.

---

## 10. Testing strategy

- R73. Framework: swift-testing (`@Test`, `#expect`); table-driven cases use `@Test(arguments:)`
  (PanelKeyMap, ClipFilter, QueryParser, TextHeuristics). Fakes in `Tests/ClipjarCoreTests/Support/`:
  `FakePasteboard` (scripted types/changeCount/reps; **counts every content-data read per type**; records
  writes), `FakeAX`, `FakeKeyPoster` (counts posts), `FakeApps` (scripted frontmost/activate results,
  records call order), a shared `EventLog` to assert ordering, fixed clock, instant `sleep`, fake
  scheduler. `makeStore(_ backend:)` with **every store test parameterised over** `.memoryQueue`
  (`DatabaseQueue()`) and `.filePool` (temp-dir `DatabasePool`, WAL — the production config); temp dirs
  removed after each test. One test asserts `sqlite_version()` ≥ 3.34 (trigram).
- R74. Test cases (minimum):
  - **ClipReader / ClipExtractor:** plain text; text + rtf + html kept; RTF > 2 MB dropped alone, text
    kept; string + 60 MB TIFF → text, TIFF never read; PNG + giant TIFF → PNG, TIFF never read; giant PNG
    alone → oversized; text > 1 MB → oversized; whitespace-only string + image → image; files win;
    `public.file-url` declared but `fileURLs()` empty + string → text captured (A26); link
    http/https/www; `"foo bar.com"`/`mailto:` not links; undecodable image → nil; previewText collapse +
    300-char cut; CRLF→LF hash equal, trailing-newline variants distinct (R17).
  - **ClipFilter:** each reason incl. ordering (marker first); every `SensitiveTypes` member; timed pause
    expired → accept; indefinite pause; ignored id incl. `com.apple.Passwords`; own bundle id; defaults.
  - **ClipboardWatcher:** no change → no sink; captured once; paused/ignored/concealed/marker → **zero
    data reads**; paused content not captured after resume; declared source preferred; Clipjar frontmost →
    `source == nil`; activation sequence [ignored → other] within one tick → rejected (R82); ignored app
    activated, ≥ 1 idle tick, then a copy in another app → accepted (N4); launch capture;
    ordered ingest through the AsyncStream consumer (3 captures → 3 rows in copy order).
  - **ClipStore:** insert each kind; bump updates `lastCopiedAt`/source, fills missing rtf, keeps
    `createdAt`/`isPinned`/`plainText`, writes no new blob; image bump with missing blob/thumb rewrites
    them (R19); same text different kind = two rows; two `ClipStore`s on one temp-file pool ingesting the
    same image concurrently → one row, blobs present (R31); FTS substring, mid-word; `cafe`→"Café",
    `ä`→"Äpfel" (R80); short LIKE with `%`/`_` escaped; app/kinds/pinnedOnly filters; pin/unpin; deleted,
    pruned and cleared clips **no longer match search**; delete/clear/prune remove blobs; clearAll keeps
    pins; synthetic secret absent from `clips.sqlite*` bytes right after user delete (R83); 50 ingests at
    the limit run `optimize` ≤ 1 time, and `scrubIfPending` after pruning removes pruned text (N1);
    image bump with missing files: files written before the transaction (N7); `delete(id:ifLastCopiedAt:)`
    after a bump deletes nothing (N3); prune by limit
    excludes pins; age prune excludes pins; ingest triggers prune with configured limit; prune error →
    ingest still `.inserted`; `pruneCount` matches `prune`; blob write failure (unwritable blobs dir) → no
    row, error thrown; thumbnail failure → row with `thumbnailPath == nil`; orphan cleanup grace +
    referenced files; migrations idempotent; paging; `payload` per kind.
  - **StoreOpener:** garbage `clips.sqlite` → `-wal`/`-shm`/`blobs` moved with one stamp, collision gets
    `-2`, `recoveredFromCorruption`; healthy → false and no checks run without flag; `.needs-repair` +
    tampered FTS shadow table (`DELETE FROM clip_fts_data WHERE id > 1`) → repaired, search works, flag
    removed, nothing moved; support path is a regular file → in-memory store + `storageUnavailable`;
    second `InstanceLock` on the same dir → `.heldByOther`; lock path is a directory/regular-file conflict
    → `.failed` (not `.heldByOther`) (N2); dir `0700`, db/wal/blob files `0600`.
  - **QueryParser:** terms, quoted phrase, `@app`, multiple `@`, each `is:`, `is:pinned`, unknown `is:x`
    literal, bare `@` ignored, case-insensitive, chip ∩ token kinds incl. empty intersection.
  - **HistoryViewModel:** initial selection; bounds; page; ⌘N incl. out-of-range beep; tab cycling;
    Esc order (toast → query → close); selection kept on DB update; selection after delete (middle/last);
    filter change resets; paging trigger; hover ignored without mouse movement and within 150 ms of a
    key move; delete → row hidden + toast, ⌘Z restores row and selection; commit on toast expiry, on
    panel close, on next delete; delete → same content re-copied → expiry → row present and visible (N3);
    paging continues while a deletion is pending (A24); pinned needs second ⌘⌫ within 2 s; `matchCount`
    vs `allCount`;
    `prepareForOpen` awaits age prune before the first rows emission (D11, N6); banners logic.
  - **Paster:** order = write → close completes (not key) → activate → ⌘V (EventLog); copyOnly / not
    trusted / pasteOnSelect off / `target == nil` / `activate` false / frontmost timeout → **zero posts**,
    payload still written; trusted path posts exactly once; `touch` throwing does not affect outcome;
    missing payload → nothing written.
  - **SettingsStore:** defaults, round-trip, timed pause fires via fake scheduler → `isPaused == false`
    and observers notified, re-armed on init, expired pause cleared, FilterSettings snapshot.
  - **PanelPlacement:** status-item, cursor, flip above, centred, clamping each edge, negative-origin screen.
  - **PanelKeyMap:** every §6.3 row incl. ⌘Q → close; ⌘A/⌘C/⌘V/⌘X → nil; ⌘Z → nil unless toast visible.
  - **TextHeuristics / Highlighter:** hex 3/6/8 ± `#`, invalid; code-like; highlight folding, no
    overlap, cap 50.
- R75. **Manual (not automated):** panel visuals light/dark, Increase Contrast, Reduce Motion; real paste
  into TextEdit/Safari/Terminal; ⌘A/⌘C/⌘V/⌘X/⌘Z in the search field and Settings, ⌘W closes Settings;
  Japanese IME composition with ⏎/↑/↓/Esc in the search field; hotkey recorder: system-shortcut conflict
  blocked and previous value still shown, ⇧-only rejected, clearing; reopen from Finder opens panel;
  first-run panel; launch at login; Safari/Chrome "Copy Image" captures an image (not only its URL);
  fresh-user pasteboard prompt and Deny → banner on macOS 15.4+/26; App Translocation banner when run
  from Downloads; Gatekeeper first run from a downloaded zip on a second Mac/user account.
- R76. **Smoke check before merging to `main`:** `make clean`, `make test`, `make install`; before launching, seed the
  clipboard with synthetic text (`printf 'Hello, Clipjar' | pbcopy`); launch `/Applications/Clipjar.app`;
  clear history; copy 3 synthetic texts, 1 `example.com` URL, 1 generated image, 1 file under `/tmp`
  (R79); open via ⇧⌘V; verify rows, preview, search, chips; capture the **panel window only**
  (`screencapture -o -l <windowID> /tmp/clipjar-panel.png`) and visually review it for anything
  non-synthetic before committing it as the README screenshot; open Settings and confirm the Recorder renders (proves the
  resource bundle is found, R9).
- R79. **Synthetic data only (public repo).** Test fixtures, sample strings, README screenshots and
  smoke-check clips MUST use synthetic content only (e.g. `"Hello, Clipjar"`, `https://example.com/docs`,
  `#FF8800`, a generated solid-colour PNG, files under a temp dir). Never include real clipboard
  contents, credentials/tokens, employer or company names, internal URLs, ticket keys, chat links,
  personal email addresses, or local user paths (`/Users/<name>/…`) in sources, tests, docs,
  screenshots or commit messages. Screenshots are taken with a history containing only
  the R76 synthetic clips, and source-app names shown must be stock macOS apps (TextEdit, Safari, Finder).

---

## 11. Size budget and scope cuts

- R77. Realistic estimate after review: ClipjarCore ~1,600; Clipjar target + views ~1,450; tests ~1,300;
  Makefile/plist/workflows/README ~300 — **~4,650 lines total**. There is no PR: work merges straight to
  `main`, so the earlier 4,000-line / 75-file / 200 KB PR cap **no longer applies**. Keep commits small
  and conventional; CI must be green on `main`.
- R78. If scope must shrink (e.g. time), cut **in this order** and record the cut in the commit message
  and README:
  1. `@app` / `is:` search tokens (QueryParser keeps plain terms + quotes only; chips remain).
  2. Hex colour swatch (R20).
  3. Max-age pruning (R32 step 1 and its Settings picker).
  **Never cut:** configurable hotkey, paste (incl. copy-only fallback), pinning, preview pane, privacy
  filter, type filters/chips, portability (universal build, CI, release, README install).
