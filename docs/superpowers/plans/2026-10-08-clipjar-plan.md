# Clipjar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Clipjar v1 — a native macOS 14+ menu bar clipboard history manager with a keyboard-first floating panel, search, pins, preview, privacy filtering and paste-into-previous-app — as a SwiftPM package with a unit-tested core and a thin app shell.

**Architecture:** `ClipjarCore` (library) holds all logic — models, GRDB/SQLite store with trigram FTS5, capture pipeline behind a pasteboard protocol, query parser, paster, settings and the `@Observable` view model — and is tested with swift-testing using fakes and in-memory/temp-file databases. `Clipjar` (executable, MainActor default isolation) is AppKit/SwiftUI glue: status item, hotkey, non-activating panel, views, settings window, launch wiring. A Makefile assembles, ad-hoc signs and zips a universal `.app`; GitHub Actions runs CI and tag releases.

**Tech Stack:** Swift 6 (tools 6.2), SwiftPM, AppKit + SwiftUI, GRDB.swift 7.11.1 (exact), KeyboardShortcuts 3.1.0 (exact), swift-testing, CryptoKit, ImageIO, Make, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-08-clipjar-design.md` (R1–R94; R95 unused). Standing decisions: `/tmp/clipjar/design-brief.md`.

## Plan files

| File | Tasks |
|---|---|
| `2026-10-08-clipjar-plan-part-1.md` | 1–17 Foundation, models, store, opener, lock |
| `2026-10-08-clipjar-plan-part-2.md` | 18–35 Capture, search, paste, settings, view model, display helpers |
| `2026-10-08-clipjar-plan-part-3.md` | 36–49 App target, packaging, release, README, smoke check |

**Dispatching:** tasks run strictly in order, one implementer per task. Each brief = the **Common Brief**
below + the single task section copied verbatim. Implementers do not read the plan or spec.

---

## Common Brief (paste into every implementer brief)

> You are implementing one task of Clipjar, a public MIT macOS app. Run everything
> from the repository root (the controller gives the absolute path in the brief).
> - **Toolchain:** Swift 6.4 / Xcode 27 on macOS 26 locally; `swift-tools-version: 6.2`; deployment macOS 14.
>   CI builds with Xcode 26.0 (Swift 6.2), so use no language features newer than Swift 6.2. Swift 6
>   language mode, strict concurrency: **no** `@unchecked Sendable`, `nonisolated(unsafe)`,
>   `DispatchQueue.main.sync`. GRDB.swift 7.11.1, KeyboardShortcuts 3.1.0 (3.x uses `Name("…", initial:)`).
> - **Tests:** swift-testing only (`import Testing`, `@Suite`, `@Test`, `#expect`, `@Test(arguments:)`).
>   Tests use `@testable import ClipjarCore`. Shared helpers live in `Tests/ClipjarCoreTests/Support/`;
>   reuse existing helpers before adding new ones. Use whole-second dates (GRDB stores ms precision), e.g.
>   `t0 = Date(timeIntervalSince1970: 1_800_000_000)`. MainActor types → `@MainActor` suites.
> - **TDD:** write the listed tests first; run the given `swift test --filter …` and see them fail (compile
>   failure for missing symbols counts); implement the minimum; re-run until green; run `swift build`
>   (no new warnings) and the full `swift test`. Tasks marked "no assertable behaviour" verify with the
>   commands given instead.
> - **Public repo / synthetic data only:** fixtures and examples use values like `"Hello, Clipjar"`,
>   `https://example.com/docs`, `#FF8800`, generated solid-colour images, temp-dir files. Never real
>   clipboard content, credentials, company names, internal URLs, ticket keys, emails or `/Users/<name>` paths.
> - **Logging:** `Log.<category>` (`os.Logger`, subsystem `com.vtrifonov.clipjar`). Never log clip
>   content, previews, clip file paths or content hashes; errors as domain + code only; bundle ids only at
>   `.debug` with `privacy: .private`.
> - **No networking code** anywhere in `Sources/` (CI greps for `URLSession`, `Network`, `socket(`,
>   `connect(` …); don't name functions `connect(`/`socket(`.
> - **Shell:** one command per Bash call; no `&&` chains, no multi-line commands. Use `rg`/`fd`.
> - **Commit:** stage only the task's files; plain conventional-commit message exactly as given in the task.
>   **No AI attribution of any kind** (no `Co-Authored-By`, no `Claude-Session`, no "Generated with" lines).
> - If an existing file from an earlier task uses a slightly different name/label than this brief, follow
>   the existing code and mention it in your report. Report: files changed, test names + pass/fail output
>   summary, commit SHA.

---

## Global Constraints

- Product "Clipjar", bundle id `com.vtrifonov.clipjar`, targets `Clipjar` / `ClipjarCore` / `ClipjarCoreTests`.
- `// swift-tools-version: 6.2`, `platforms: [.macOS(.v14)]`, Swift 6 mode (R6). Dependencies exactly
  KeyboardShortcuts `3.1.0` and GRDB.swift `7.11.1`, both MIT (R7). `ClipjarCore` has no SwiftUI views and
  no KeyboardShortcuts dependency (R8).
- No `.xcodeproj`; build via SwiftPM + Makefile (R1). Universal arm64 + x86_64 (R69). No absolute or user
  paths anywhere (R4, R69).
- Local only: no network code, no analytics, no crash reporting, no update checks; not sandboxed; no
  entitlements (R64). Unencrypted at rest, documented (R66).
- Non-goals (R5): no sync, encryption, snippets, clip editing, App Store/sandbox, Developer ID/notarization,
  Sparkle, custom icon artwork, localisation, plain-text-paste mode.
- Logging rules R67 (see Common Brief).
- Size/scope (R77, R78): no PR cap (merges to `main`); if scope must shrink cut in order `@app`/`is:` tokens
  → hex swatch → max-age pruning, and record the cut in the commit message and README. Never cut:
  configurable hotkey, paste + copy-only fallback, pinning, preview, privacy filter, chips, portability.
- Synthetic data only (R79). Commit messages plain conventional commits, no AI attribution.

## Review Focus

Inputs the spec implies but does not spell out, most likely first; each has a pinning test in its owning task:

1. **Emoji / grapheme clusters in previews and highlights** — truncation never splits a cluster; highlight
   ranges stay valid. Tests: Task 4 `previewIsGraphemeSafe`, Task 25 `emojiTextRangesValid`.
2. **Search text containing FTS5 syntax** (`"`, `*`, `NEAR(`, `-`, `(`, `OR`) — treated literally, never
   throws. Test: Task 6 `ftsSyntaxIsLiteral`.
3. **File paths with spaces / non-ASCII** — round-trip through capture, storage and paste unchanged.
   Tests: Task 8 `ClipBuilderTests.fileClip`, Task 11 `payloadFilesRoundTripUnicode`.
4. **Extreme image aspect ratios** (1×4000) — thumbnail is valid, not zero-width. Test: Task 7
   `thumbnailExtremeAspect`.
5. **Very large multi-file copies** (1,000 Finder items) — captured, preview stays ≤ 300 chars. Test:
   Task 20 `thousandFilesCaptured`.

---

## Task list

`[C]` = complex / cross-cutting. Verification for core tasks is `swift test --filter <Suite>`; app tasks
are `swift build` + full `swift test` (+ manual in Task 49).

| # | Task | Part | Verify |
|---|---|---|---|
| 1 | Package skeleton + SQLite capability | 1 | `SQLiteCapabilityTests` |
| 2 | Makefile build/test/clean, CI, no-network script | 1 | `make test`, script, shellcheck |
| 3 | Models, content hash, folding, Log | 1 | `ContentHashTests`, `SearchFoldingTests` |
| 4 | Text heuristics + preview text | 1 | `TextHeuristicsTests` |
| 5 | Schema, migrator, DB config, fixtures | 1 | `SchemaTests` |
| 6 | ClipQuery → SQL | 1 | `ClipQueryTests` |
| 7 | Blob files + thumbnails | 1 | `BlobFilesTests` |
| 8 | ClipBuilder + ingest text/link/file [C] | 1 | `ClipBuilderTests`, `ClipStoreIngestTests` |
| 9 | Image ingest, blob repair, rollback [C] | 1 | `ClipStoreImageTests` |
| 10 | Pruning | 1 | `ClipStorePruneTests` |
| 11 | Mutations, conditional delete, payloads | 1 | `ClipStoreMutationTests` |
| 12 | Secure deletion + deferred scrub [C] | 1 | `ClipStoreScrubTests` |
| 13 | Observations + orphan cleanup | 1 | `ClipStoreObservationTests` |
| 14 | InstanceLock | 1 | `InstanceLockTests` |
| 15 | StoreOpener layout/perms/fallback | 1 | `StoreOpenerTests` |
| 16 | StoreOpener corruption + repair [C] | 1 | `StoreOpenerRecoveryTests` |
| 17 | StoreEvent + runtime corruption flag | 1 | `StoreEventTests` |
| 18 | Pasteboard constants + ClipFilter | 2 | `ClipFilterTests` |
| 19 | PasteboardReading, FakePasteboard, ClipReader | 2 | `ClipReaderTests` |
| 20 | ClipExtractor | 2 | `ClipExtractorTests` |
| 21 | SystemPasteboard adapter | 2 | `SystemPasteboardTests` |
| 22 | ClipboardWatcher [C] | 2 | `ClipboardWatcherTests` |
| 23 | CaptureQueue | 2 | `CaptureQueueTests` |
| 24 | QueryParser + FilterChip | 2 | `QueryParserTests` |
| 25 | Highlighter | 2 | `HighlighterTests` |
| 26 | Paster [C] | 2 | `PasterTests` |
| 27 | System paste adapters | 2 | `SystemPasteAdaptersTests` |
| 28 | SettingsStore + pause timer | 2 | `SettingsStoreTests` |
| 29 | RetentionChanger | 2 | `RetentionChangerTests` |
| 30 | PanelCommand + PanelKeyMap | 2 | `PanelKeyMapTests` |
| 31 | PanelPlacement | 2 | `PanelPlacementTests` |
| 32 | HistoryViewModel core [C] | 2 | `HistoryViewModelTests` |
| 33 | HistoryViewModel delete/undo [C] | 2 | `HistoryViewModelDeleteTests` |
| 34 | HistoryViewModel open/banners | 2 | `HistoryViewModelOpenTests` |
| 35 | DisplayFormat, ImageDecoder, OpenGate | 2 | `DisplayFormatTests`, `ImageDecoderTests`, `OpenGateTests` |
| 36 | App entry + hidden main menu | 3 | build |
| 37 | StatusItemController | 3 | build |
| 38 | HotkeyController | 3 | build |
| 39 | PanelController + ClipjarPanel [C] | 3 | build |
| 40 | ImageCache, ClipRowView, list | 3 | build |
| 41 | PreviewView | 3 | build |
| 42 | Banners, toast, states | 3 | build |
| 43 | HistoryView composition | 3 | build |
| 44 | Settings window | 3 | build |
| 45 | Launch sequence + lifecycle wiring [C] | 3 | build, `swift run` launches |
| 46 | Info.plist + Makefile app/sign/zip/install | 3 | `make app`, `make zip`, codesign verify |
| 47 | Release workflow | 3 | `yq` checks |
| 48 | README | 3 | `rg` privacy check |
| 49 | Smoke check + manual checklist + screenshot | 3 | manual (R75, R76) |

---

## Requirement → task → verification matrix

| R | Task(s) | Verified by |
|---|---|---|
| R1 | 1, 2, 46 | build; `make app` |
| R2 | 13, 32, 39, 49 | `pagedQueryReturnsNewest`, `pagingTrigger`; panel reused; manual |
| R3 | 18, 22 | `ClipFilterTests`, watcher zero-read tests |
| R4 | 46, 47, 48 | `make app` lipo check; release yml; README |
| R5 | Global | review |
| R6, R7, R8 | 1 | package builds |
| R9 | 46, 49 | `test -d …KeyboardShortcuts_KeyboardShortcuts.bundle`; Recorder renders |
| R10, R11 | 2, 46 | make targets |
| R12 | 46 | `plutil -lint`, PlistBuddy |
| R13 | 5 | `migrationsIdempotent` |
| R14 | 1, 5, 6 | `trigramTokenizerAvailable`, `ftsTriggersTrackInsertUpdateDelete`, `substringMatchesMidWord` |
| R15 | 20 | `ClipExtractorTests` |
| R16 | 4, 8 | `previewCollapsesWhitespace`, `previewCutsAt300Characters`, `ClipBuilderTests` |
| R17 | 3 | `ContentHashTests` |
| R18 | 4, 20 | `isLink` table, `linkKind` |
| R19 | 8, 9 | `bumpUpdatesRecencyAndSource`, `bumpFillsOnlyMissingRichData`, `bumpRepairsMissingFiles` |
| R20 | 4, 40 | `hexColor` table; manual swatch |
| R21 | 4, 40 | `isCodeLike` table; manual |
| R22 | 7, 15 | `writeIfAbsentCreatesPrivateFile`, `freshOpenCreatesPrivateLayout`, `permissionsReappliedOnOpen` |
| R23 | 7, 9 | `thumbnailLongestEdge112`, `insertWritesBlobAndThumbnail` |
| R24 | 19 | oversize tests in `ClipReaderTests` |
| R25 | 21 | `SystemPasteboardTests` |
| R26, R27 | 18 | `ClipFilterTests` |
| R28, R29 | 22 | `startPollsImmediately`, `launchClipboardNotCaptured`, `pausedContentNotCapturedAfterResume` |
| R30 | 23, 45 | `itemsBufferedBeforeStartAreIngestedInOrder` |
| R31 | 8, 9, 10 | single-transaction tests, `transactionFailureRemovesOnlyNewFiles`, `pruneErrorDoesNotFailIngest` |
| R32 | 10, 34, 45 | `ClipStorePruneTests`, `openPrunesBeforeFirstRows` |
| R33 | 11 | `deleteRemovesRowAndBlobs`, `clearAllKeepsPinned` |
| R34 | 13, 45 | `orphanCleanupHonoursGraceAndReferences` |
| R35 | 15, 16 | `StoreOpenerTests`, `StoreOpenerRecoveryTests` |
| R36 | 6 | `ClipQueryTests` |
| R37 | 26 | `PasterTests` |
| R38 | 27, 49 | build; manual paste |
| R39 | 27, 39 | `handleFromRunningApplication`; manual |
| R40, R41 | 38, 49 | manual (hotkey, clear) |
| R42 | 44, 49 | manual conflict check |
| R43 | 39 | manual |
| R44 | 31, 39 | `PanelPlacementTests` |
| R45 | 34, 39 | `prepareForOpenResets` |
| R46 | 39, 49 | manual dismiss paths |
| R47 | 34, 42 | `systemBannersReevaluatedOnOpen`, banner tests; manual |
| R48 | 13, 32 | `pagingTrigger`, observation tests |
| R49 | 24, 32 | `QueryParserTests`, `querySearchesAndHighlights` |
| R50 | 32, 33 | selection tests |
| R51 | 32, 33 | command tests |
| R52 | 25, 40 | `HighlighterTests` |
| R53 | 28 | `SettingsStoreTests` |
| R54 | all core tasks | Swift 6 strict build |
| R55, R55a | 37, 39, 40, 42, 43, 49 | manual (motion, contrast) |
| R56, R57 | 35, 43 | `countLabel`; manual |
| R58 | 35, 40 | `secondaryLine*`; manual |
| R59 | 35, 41 | `previewSummary`; manual |
| R60 | 35, 43 | `footerHints` |
| R61 | 37, 49 | manual |
| R62 | 44, 49 | manual |
| R63 | 35, 40–44 | `rowAccessibilityLabel`; manual VoiceOver |
| R64 | 2 | `scripts/check-no-network.sh` in CI |
| R65 | 18, 22 | zero-read tests |
| R66 | 12, 15, 48 | scrub byte tests; perms tests; README |
| R67 | 3, all | review (Common Brief rule) |
| R68 | 27, 48 | review; README |
| R69 | 2, 46 | lipo check; no-paths review |
| R70 | 1, 2, 46 | CI yml; `Package.resolved` committed |
| R71 | 47 | `yq` checks |
| R72 | 48 | README review |
| R73 | 1, 5, all core | swift-testing; backends fixture |
| R74 | 3–35 | the named tests (one-to-one with R74 bullets) |
| R75 | 49 | manual checklist |
| R76 | 49 | smoke steps |
| R77, R78 | Global, 48 | review |
| R79 | Global, 48, 49 | fixtures review; screenshot inspection |
| R80 | 3, 6 | `foldsCaseAndDiacritics`, `caseAndDiacriticFolding` |
| R81 | 19, 22 | `stringPlusHugeTiffNeverReadsTiff`, `pngPreferredTiffNeverRead`, `*ReadsNoData` |
| R82 | 22 | `ignoredActivatedWithinTickRejected`, `ignoredFrontmostAtLastTickRejected`, `staleActivationClearedAfterIdleTick` |
| R83 | 5, 12, 45 | `secureDeleteIsOn`, `ClipStoreScrubTests`; terminate scrub |
| R84 | 16, 17, 45 | `repairFlagRepairsTamperedFTS`, `corruptErrorWritesFlag` |
| R85 | 14, 45 | `InstanceLockTests`; manual second launch |
| R86 | 23, 35, 45 | `OpenGateTests`, `CaptureQueueTests`; manual |
| R87 | 11, 33 | `conditionalDeleteAfterBumpDeletesNothing`, `HistoryViewModelDeleteTests` |
| R88 | 28 | `timedPauseFires`, `rearmedOnInit` |
| R89 | 29, 44 | `RetentionChangerTests`; manual dialog |
| R90 | 35, 40, 41 | `ImageDecoderTests`; manual |
| R91 | 36, 49 | manual ⌘A/⌘C/⌘V/⌘X/⌘Z |
| R92, R93 | 42, 45, 49 | `systemBannersReevaluatedOnOpen`; manual |
| R94 | 30, 39, 49 | `PanelKeyMapTests`; manual IME |

---

## Invariants and edge cases (TDD list for stateful mechanisms)

**Ingest / dedup / bump (Tasks 8, 9, 23)**
- Lookup-by-hash and insert/bump happen in one write transaction; two stores ingesting the same image
  concurrently yield one row (`concurrentStoresSameImage`).
- Bump changes only `lastCopiedAt`, source (when non-nil) and missing rich data / blob paths; never
  `createdAt`, `isPinned`, `plainText`, and never fires the FTS update trigger.
- Hash includes kind and CRLF-normalised text; RTF/HTML/source never hashed.
- File IO precedes the transaction; a failed transaction removes only files this call created.
- Blob write failure → no row; thumbnail failure → row without thumbnail.
- Captures are ingested in copy order, including those buffered before the store opened; an ingest error
  emits `.writeFailed` and the consumer keeps going.

**Prune / scrub (Tasks 10, 12)**
- Pinned rows never count toward the limit and are never pruned (limit and age).
- Ordering tie-break `lastCopiedAt DESC, id DESC` everywhere.
- Rows deleted before files; file-removal errors swallowed; orphan cleanup respects a 60 s grace.
- `pruneCount` == `prune` result and is read-only.
- User deletions scrub immediately (secret bytes absent from `clips.sqlite*`); prune deletions defer
  `optimize` to ≤ 1 per hour (≤ 1 for 50 consecutive ingests) and `scrubIfPending` completes it.
- A prune failure after an insert never fails the ingest.

**Pending delete / undo (Tasks 11, 33, 39, 45)**
- At most one pending deletion; starting another commits the previous one.
- Commit points: toast expiry (5 s), Esc/dismiss with toast, next delete, panel hide, app terminate.
- Commit is `DELETE … WHERE id = ? AND lastCopiedAt = ?`; a re-copy during the window keeps the row visible.
- Undo only while the delete toast is visible; restores row and selection.
- Pinned clips need a second ⌘⌫ within 2 s.
- Paging uses the pre-filter fetched count, so it continues while a row is hidden.

**Single-instance lock (Task 14, 45)**
- `.heldByOther` only on `EWOULDBLOCK`; every other failure is `.failed(errno)` → in-memory + banner, never exit.
- Lock held for the process lifetime; released on deinit.

**Corruption repair (Tasks 15–17)**
- CORRUPT/NOTADB at open → move aside db, `-wal`, `-shm`, `blobs` with one stamp (+`-2`… on collision);
  nothing deleted; fresh store; Recovered banner.
- Runtime CORRUPT → `.needs-repair` flag (0600) + banner; next launch runs FTS integrity-check/rebuild,
  REINDEX, integrity_check; healthy → flag removed, no move-aside. No flag → no checks.
- Any other open failure → in-memory store + Storage-unavailable banner.
- Support dir/blobs `0700`, db/wal/shm/blobs `0600`, excluded from backup — re-applied every launch.

**Watcher attribution / self-capture (Tasks 18, 19, 22, 36)**
- `lastChangeCount` advances before filtering, so paused/ignored content is never captured later.
- Preflight (marker, pause, concealed/sensitive, transient, auto-generated, ignored/own app) reads zero
  content data; then only the chosen representation is read (never TIFF when PNG or text exists).
- Candidates = declared source, frontmost at last tick, apps activated since last tick, frontmost now;
  tick state resets on every tick, including no-change ticks.
- Clipjar's own writes (paste and Edit ▸ Copy/Cut) carry the marker; Clipjar as a candidate rejects the clip.

**Paste sequencing (Task 26, 39)**
- Order: write → panel ordered out and not key → activate → frontmost verified (≤ 250 ms) → 40 ms →
  re-verify → exactly one ⌘V.
- Any of copy-only, paste disabled, untrusted, no target, activation refused, timeout, lost focus → zero
  ⌘V, payload still written. Missing payload → beep, nothing written, panel not closed.
- `touch` is fire-and-forget; its failure never changes the outcome.

**Pause timer (Task 28, 37, 45)**
- Timed pause fires at `pausedUntil`, clearing both keys and notifying observers; re-armed on launch;
  expired pause cleared on launch; resume/new pause cancels the old timer; indefinite pause never schedules.

---

## Spec gap decisions taken in this plan (shape only, no design change)

- `HistoryActions` (closure struct), `PendingDeletion`, `openGeneration`, `scrollTarget`, `select(id:)`,
  `activate(id:copyOnly:)`, `takePendingDeletionForTermination()` and an injected `scheduler` on
  `HistoryViewModel` — needed by R86's ≤ 2 s off-main terminate commit and by testable timers.
- `ClipRow.fileCount` (`json_array_length(fileURLs)`) for the "3 files" row text (R58).
- `OpenResult` gains `storageUnavailable`, `ranRepairChecks`, `supportDirectory`; `ClipStore.close()`.
- `ClipboardWatcher` gains `runningAppName` for R29's "if a running app has that bundle id". Spec R26
  rejects Clipjar as a candidate, so R74's "Clipjar frontmost → source nil" is asserted as "not captured"
  plus `attributedSource(...) == nil`.
- New small core units: `ContentHash`, `ClipBuilder`, `CaptureQueue`, `StoreErrorClassifier`,
  `RetentionChanger`, `OpenGate`, `DisplayFormat`, `ImageDecoder`, `Schedulers`; app files `ImageCache.swift`,
  `StateViews.swift`; `scripts/check-no-network.sh`, `scripts/window-id.swift`.
- `Paster` gains a `clock` parameter for `touch`.
