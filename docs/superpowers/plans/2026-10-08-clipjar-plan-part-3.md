# Clipjar Plan — Part 3: App target, distribution, smoke check (Tasks 36–49)

Index, global constraints, Common Brief, requirement matrix and invariants:
`docs/superpowers/plans/2026-10-08-clipjar-plan.md`. **Dispatcher:** paste the Common Brief from the
index plus exactly one task section below into each implementer brief.

All app-target code lives in `Sources/Clipjar/` (MainActor default isolation, may `import
KeyboardShortcuts`). These tasks are thin AppKit/SwiftUI glue over the unit-tested `ClipjarCore`; unless a
task lists tests, its verification is `swift build` (zero warnings in our targets) plus
`swift test` (whole suite still green), and its behaviour is checked manually in Task 49 (R75).

Core API these tasks consume (all exist after Part 2): `AppIdentity`, `Log`, `SettingsStore`
(`historyLimit`, `maxAgeDays`, `ignoredBundleIDs`, `hasLaunchedBefore`, `pasteOnSelect`, `isPaused`,
`pausedUntil`, `pause(for:)`, `resume()`, `filterSettings`), `Schedulers.timer`, `RetentionChanger`
(`propose`, `apply`, `RetentionDecision`), `ClipStore` (`ingest`, `prune`, `configure`, `clearAll`,
`scrubIfPending`, `delete(id:ifLastCopiedAt:)`, `cleanOrphanBlobs`, `clipObservation`, `blobsDirectory`),
`StoreOpener` (`defaultSupportDirectory`, `open`, `openInMemory`, `OpenResult`), `InstanceLock`,
`StoreEvent`, `StoreErrorClassifier`, `CaptureQueue`/`CaptureItem`, `ClipboardWatcher`,
`SystemPasteboard`, `PasteboardTypes`, `Paster`, `PasteOutcome`, `SourceAppHandle`,
`SystemAccessibility`, `SystemKeyPoster`, `SystemAppActivator`, `HistoryViewModel` (+ `HistoryActions`,
`Banner`, `Toast`, `PendingDeletion`, `FilterChip`, `PanelCommand`), `PanelKeyMap`, `PanelPlacement`,
`OpenGate`/`OpenPlacement`, `DisplayFormat`, `ImageDecoder`, `Highlighter`, `TextHeuristics`, `SourceApp`.

---

### Task 36: App entry point and hidden main menu

**Requirements:** R54, R91 (incl. N5 marker on own copies).
No assertable unit behaviour (AppKit menu wiring); manual check in Task 49 (⌘A/⌘C/⌘V/⌘X/⌘Z in fields).

**Files:**
- Modify: `Sources/Clipjar/main.swift`
- Create: `Sources/Clipjar/AppDelegate.swift`, `Sources/Clipjar/MainMenu.swift`

**Interfaces — Produces:**
```swift
// main.swift
import AppKit
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    let editActions = ClipjarEditActions()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(editActions: editActions)     // step 1 of R86; Task 45 adds the rest
    }
}
enum MainMenu { static func build(editActions: ClipjarEditActions) -> NSMenu }
final class ClipjarEditActions: NSObject {
    @objc func clipjarCopy(_ sender: Any?)
    @objc func clipjarCut(_ sender: Any?)
}
```

**Behaviour (R91):** menu built in code (never visible for an LSUIElement app; key equivalents route
through it):
- App menu: "About Clipjar" → `NSApplication.orderFrontStandardAboutPanel(_:)`; "Settings…" ⌘, → action
  `Selector(("openSettings:"))`, target `nil` (AppDelegate implements it in Task 45; disabled until then);
  separator; "Quit Clipjar" ⌘Q → `NSApplication.terminate(_:)`.
- Edit: Undo ⌘Z (`undo:`), Redo ⇧⌘Z (`redo:`), separator, Cut ⌘X → `clipjarCut:` target `editActions`,
  Copy ⌘C → `clipjarCopy:` target `editActions`, Paste ⌘V (`paste:`), Select All ⌘A (`selectAll:`).
- Window: Close ⌘W → `performClose:`.
- `clipjarCopy`/`clipjarCut`: `let before = NSPasteboard.general.changeCount`;
  `NSApp.sendAction(#selector(NSText.copy(_:)) /* or cut */, to: nil, from: sender)`; if
  `NSPasteboard.general.changeCount != before` → `NSPasteboard.general.pasteboardItems?.first?.setData(Data(),
  forType: .init(PasteboardTypes.marker))`. So text copied inside Clipjar is never captured (N5).

**Verification:** `swift build`; `swift test`.
**Commit:** `git add Sources/Clipjar` → `git commit -m "feat(app): add app entry point and hidden main menu"`.

---

### Task 37: StatusItemController

**Requirements:** R61, R55a (capture pulse; none under Reduce Motion), R63 (status item label).
No assertable unit behaviour (NSStatusItem UI); manual check in Task 49.

**Files:** Create `Sources/Clipjar/StatusItemController.swift`

**Interfaces — Produces:**
```swift
final class StatusItemController: NSObject {
    init(settings: SettingsStore,
         onToggle: @escaping () -> Void,          // left click
         onOpen: @escaping () -> Void,            // menu "Open Clipjar"
         onOpenSettings: @escaping () -> Void)
    var buttonScreenFrame: NSRect? { get }        // button.window.convertToScreen(button.convert(button.bounds, to: nil))
    func pulse()
}
```

**Behaviour:**
- `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`; image
  `NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipjar")` with
  `.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))`, `isTemplate = true`.
- `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`; action: if the current event is a right click or has
  `.control` → pop up the menu (`menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)`);
  else `onToggle()`.
- Menu: "Open Clipjar" (shows the hotkey: `item.setShortcut(for: .togglePanel)` from KeyboardShortcuts —
  available after Task 38; until then plain item), separator, "Pause for 15 Minutes" →
  `settings.pause(for: 900)`, "Pause"/"Resume" (title by `settings.isPaused`) → `pause(for: nil)` /
  `resume()`, separator, "Settings…" ⌘, → `onOpenSettings()`, "Quit Clipjar" ⌘Q → `NSApp.terminate(nil)`.
- Paused state: `button.appearsDisabled = settings.isPaused`; `toolTip = isPaused ? "Clipjar — paused" : "Clipjar"`.
  Keep it live with an observation loop:
  `func track() { withObservationTracking { refresh() } onChange: { Task { @MainActor [weak self] in self?.track() } } }`.
- `pulse()`: unless `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, animate `button.alphaValue`
  1 → 0.35 → 1 over 300 ms total (two 150 ms `NSAnimationContext` groups; hop back to the main actor in the
  completion handler with `MainActor.assumeIsolated`).

**Verification:** `swift build`; `swift test`.
**Commit:** `git commit -m "feat(app): add menu bar status item with pause menu and capture pulse"`.

---

### Task 38: HotkeyController

**Requirements:** R40, R41, §8 "Hotkey registration fails silently".
No assertable unit behaviour (KeyboardShortcuts global registration needs the `.app`, R9).

**Files:** Create `Sources/Clipjar/HotkeyController.swift`; Modify `Sources/Clipjar/StatusItemController.swift`
(use `setShortcut(for: .togglePanel)` on "Open Clipjar").

**Interfaces — Produces:**
```swift
import KeyboardShortcuts
extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", initial: .init(.v, modifiers: [.command, .shift]))   // 3.x API: `initial:`
}
final class HotkeyController {
    init(onTrigger: @escaping () -> Void)          // KeyboardShortcuts.onKeyDown(for: .togglePanel) { onTrigger() }
    static var currentShortcutDescription: String? { KeyboardShortcuts.getShortcut(for: .togglePanel)?.description }
}
```
Persistence is KeyboardShortcuts' own `UserDefaults` key `KeyboardShortcuts_togglePanel` (survives restarts
and replacement); a cleared recorder means no global hotkey — the menu bar still works and the header hint is
hidden. Log registration at `.debug` in category `hotkey`.

**Verification:** `swift build`; `swift test`.
**Commit:** `git commit -m "feat(app): register the configurable global hotkey"`.

---

### Task 39: PanelController and ClipjarPanel **[complex]**

**Requirements:** R39 (target capture), R43, R44 (placement use), R45, R46, R55a (open/close motion),
R94 (IME pass-through), A23 (⌘Q closes), R2 (panel created once).
No new unit tests: key mapping, placement, view-model resets are already tested in Tasks 30–34; this is
window glue. Manual check in Task 49.

**Files:**
- Create: `Sources/Clipjar/PanelController.swift`
- Create: `Sources/Clipjar/Views/HistoryView.swift` (temporary minimal view; Task 43 replaces its body)

**Interfaces — Produces:**
```swift
// Views/HistoryView.swift (temporary)
struct HistoryView: View {
    let model: HistoryViewModel; let settings: SettingsStore
    var body: some View { Text("Clipjar").frame(width: 720, height: 460) }
}
final class ClipjarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class PanelController: NSObject, NSWindowDelegate {
    init(model: HistoryViewModel, settings: SettingsStore, paster: Paster,
         statusButtonFrame: @escaping () -> NSRect?)
    var isVisible: Bool { get }
    func show(_ placement: OpenPlacement)
    func toggle(_ placement: OpenPlacement)         // visible → hide(); else show
    func hide()                                     // animated
    func hideImmediately() async                    // paste/copy path
    func paste(id: Int64, copyOnly: Bool)           // wired into HistoryActions.paste (Task 45)
}
```

**Behaviour:**
- Panel created once in `init` (R43): `styleMask [.borderless, .nonactivatingPanel, .fullSizeContentView]`,
  `level .floating`, `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .transient,
  .ignoresCycle]`, `isOpaque false`, `backgroundColor .clear`, `hasShadow true`, `hidesOnDeactivate false`,
  `isMovable false`, `animationBehavior .none`, `isReleasedWhenClosed false`, size 720×460,
  `contentView = NSHostingView(rootView: HistoryView(model:settings:))`, `delegate = self`.
- `show(p)` (R45): record target = `NSWorkspace.shared.frontmostApplication` unless its bundle id is
  `AppIdentity.bundleID` → `SourceAppHandle(app)`; compute the frame: `.statusItem` →
  `PanelPlacement.belowStatusItem(buttonFrame:visibleFrame:)` on the button's screen (fallback to
  `.cursor` if no frame); `.cursor` → screen containing `NSEvent.mouseLocation` (fallback `.main`),
  `nearCursor`; `.centred` → `NSScreen.main`, `centred`. `model.prepareForOpen()`;
  `setFrame`; `makeKeyAndOrderFront(nil)`; **never** `NSApp.activate`. Install the local key monitor and
  the global mouse monitor. Open motion: unless Reduce Motion, start at `alphaValue 0` and content layer
  scale 0.97 (anchor top) → 1 over 120 ms `easeOut`; otherwise instant.
- Local key monitor (`NSEvent.addLocalMonitorForEvents(matching: .keyDown)`; body wrapped in
  `MainActor.assumeIsolated`): if the panel isn't key → return event. If `panel.firstResponder` is an
  `NSTextView` with `hasMarkedText()` → return event (R94). `cmd = PanelKeyMap.command(for: event.keyCode,
  modifiers: event.modifierFlags, deleteToastVisible: { if case .deleted = model.toast { true } else { false } }())`; if `cmd != nil &&
  model.handle(cmd!)` → return nil; else return event.
- Global monitor `[.leftMouseDown, .rightMouseDown]` → `hide()`. Both monitors removed on hide.
- Dismiss (R46): `windowDidResignKey` → `hide()` (ignored while `hideImmediately` runs); hotkey/status
  click while visible → `toggle` hides; Esc/⌘W/⌘Q arrive as `actions.close` → `hide()`.
- `hide()`: `model.commitPendingDeletion()`; remove monitors; fade `alphaValue` → 0 over 80 ms (instant
  under Reduce Motion) then `orderOut`; if `NSApp.isActive` (e.g. Settings was opened) re-activate the
  recorded target via `SystemAppActivator().activate`.
- `hideImmediately()`: commit pending deletion, remove monitors, `orderOut(nil)` (no fade), then wait
  (`Task.yield()` loop, ≤ 100 ms) until `panel.isKeyWindow == false`.
- `paste(id:copyOnly:)`: `Task { let o = await paster.perform(clipID: id, target: target, copyOnly:
  copyOnly, pasteOnSelect: settings.pasteOnSelect, closePanel: { await self.hideImmediately() });
  Log.paste.info("outcome \(String(describing: o))") }` (outcome names only — no content).

**Verification:** `swift build`; `swift test`.
**Commit:** `git commit -m "feat(app): add non-activating floating panel controller"`.

---

### Task 40: Image cache, ClipRowView and the clip list

**Requirements:** R58, R90 (row thumbnails + app icons, off-main decode, NSCache 300), R20/R21 (swatch,
SF Mono), R52 (highlights), R63 (row labels, selection traits), R55a/R58 (selection glide, Reduce Motion).
No assertable unit behaviour (SwiftUI layout); formatting/highlight logic is tested in Tasks 4, 25, 35.

**Files:** Create `Sources/Clipjar/Views/ImageCache.swift`, `Sources/Clipjar/Views/ClipRowView.swift`

**Interfaces — Produces:**
```swift
@MainActor final class ImageCache {
    static let shared = ImageCache()                      // NSCache countLimit 300 for images, separate cache for app icons
    func cachedImage(_ key: String) -> NSImage?
    func image(at url: URL, maxPixelSize: Int) async -> NSImage?
        // Task.detached { ImageDecoder.decode(url:maxPixelSize:) } → NSImage(cgImage:size:) on main; cached by "path#size"
    func appIcon(bundleID: String?) -> NSImage?
        // NSWorkspace.shared.urlForApplication(withBundleIdentifier:) + icon(forFile:), cached by bundle id
}
struct ClipListView: View {
    let model: HistoryViewModel
    // ScrollViewReader + ScrollView + LazyVStack(spacing: 2), 6 pt outer inset, width 300
}
struct ClipRowView: View {
    let row: ClipRow; let index: Int; let isSelected: Bool; let terms: [String]
    let blobsDirectory: URL; let now: Date; let selectionNamespace: Namespace.ID
}
```

**Behaviour (R58):**
- List: rows `ForEach(Array(model.rows.enumerated()), id: \.element.id)`; `.onAppear { model.rowAppeared(index:) }`;
  `.onChange(of: model.scrollTarget) { id in proxy.scrollTo(id, anchor: nil) }` (keyboard moves only);
  `.onContinuousHover` → `model.hover(id:mouseLocation: NSEvent.mouseLocation)`; tap →
  `model.activate(id:copyOnly: NSEvent.modifierFlags.contains(.option))`; context menu: Paste, Copy,
  Pin/Unpin, Delete (each `model.select(id:)` then the matching `handle(...)`, labels show ⏎ ⌥⏎ ⌘P ⌘⌫).
  A `TimelineView(.periodic(from: .now, by: 60))` supplies `now` so relative times refresh every 60 s.
- Row: min height 44, padding 8×6, `HStack(spacing: 10)`: leading 20×20 app icon (fallback
  `app.dashed` `.tertiary`); for images a 28×28 thumbnail (4 pt radius, 0.5 pt hairline, loaded via
  `ImageCache.image(at: blobsDirectory/thumbnailPath, maxPixelSize: 56)`, placeholder `photo` symbol) and the
  app icon moves to line 2 at 12×12. Line 1: `previewText`, one line, tail truncation, `.body`, SF Mono
  `.body.monospaced()` if `TextHeuristics.isCodeLike`; highlight ranges (`Highlighter.ranges`) bold +
  `accentColor` via `AttributedString`; hex colour → 12×12 swatch (3 pt radius, 0.5 pt
  `.primary.opacity(0.2)` border) before the text; links: domain part `.primary`, rest `.secondary`.
  Line 2 `.caption` `.secondary`: `DisplayFormat.secondaryLine(row, now:)`. Trailing: `pin.fill` 10 pt if
  pinned; `⌘1`…`⌘9` `.caption2` monospaced `.tertiary` for `index < 9`.
- Selection pill: `RoundedRectangle(cornerRadius: 8, style: .continuous)` fill `accentColor.opacity(0.22)`
  (Increase Contrast via `@Environment(\.colorSchemeContrast) == .increased`: 0.35 + 1 pt accent stroke),
  `matchedGeometryEffect(id: "selection", in: ns)`, animation `.spring(response: 0.22, dampingFraction: 0.9)`
  or `nil` under `@Environment(\.accessibilityReduceMotion)`.
- VoiceOver (R63): `.accessibilityElement(children: .ignore)`, label
  `DisplayFormat.rowAccessibilityLabel(row, now:)`, hint "Press Return to paste",
  `.accessibilityAddTraits(isSelected ? .isSelected : [])`, custom actions Pin/Unpin, Delete, Copy; swatch
  label "Colour #RRGGBB".

**Verification:** `swift build`; `swift test`.
**Commit:** `git commit -m "feat(app): add clip rows with thumbnails, highlights and selection pill"`.

---

### Task 41: PreviewView

**Requirements:** R59, R90 (preview image decoded off-main at pane size; cancelled on selection change;
file stats off-main), §8 "Blob missing when previewing", "File … no longer exists".
No assertable unit behaviour (SwiftUI); summary strings tested in Task 35.

**Files:** Create `Sources/Clipjar/Views/PreviewView.swift`

**Interfaces — Produces:**
```swift
struct PreviewView: View { let model: HistoryViewModel }   // reads model.selectedClip, model.highlightTerms
```

**Behaviour (R59), padding 16:** header `.caption` `.secondary`: kind icon + `DisplayFormat.previewSummary(clip)`;
second line `"Copied from <App> · <absolute date>"` (`.caption` `.tertiary`, date `.formatted(date:
.abbreviated, time: .shortened)`; omit "from <App>" if unknown); pinned badge if pinned; 12 pt gap; then:
- text/link: `ScrollView { Text(attributed) }` in `.body.monospaced()`, `.textSelection(.enabled)`, highlights
  applied; only the first 20,000 characters, then `.caption` footer "Showing first 20,000 of N characters"
  (N locale-grouped).
- image: `.task(id: clip.id)` → `ImageCache.image(at: blobs/imagePath, maxPixelSize: Int(paneSize ×
  backingScale))` (thumbnail shown meanwhile; SwiftUI cancels the task on selection change); aspect-fit, 6 pt
  radius, hairline, never upscaled beyond the image's pixel size; missing blob → "Image unavailable"
  `.secondary`. VoiceOver "Image, W by H pixels".
- files: up to 20 (then "+N more"): 32 pt workspace icon, name `.headline`, path `.caption` monospaced
  `.truncationMode(.middle)`, size via `URLResourceValues.fileSize` or "Folder"; stats/icons fetched in
  `.task(id:)` off-main (`Task.detached`); missing → `exclamationmark.triangle` + "No longer exists" `.secondary`.
- nothing selected → empty.

**Verification:** `swift build`; `swift test`.
**Commit:** `git commit -m "feat(app): add preview pane for text, images and files"`.

---

### Task 42: Banners, toast and empty/no-results/paused states

**Requirements:** R47 (banner UI and actions), §6.2 toast/empty/no-results/paused, R63 (announcements,
button labels), R92/R93 (copy), R55a (toast fade; instant under Reduce Motion).
No assertable unit behaviour (SwiftUI); banner/toast state logic tested in Tasks 33–34.

**Files:** Create `Sources/Clipjar/Views/BannerView.swift`, `Sources/Clipjar/Views/StateViews.swift`

**Interfaces — Produces:**
```swift
struct BannerView: View { let banner: Banner; let onDismiss: () -> Void }
struct ToastView: View { let toast: Toast; let onUndo: () -> Void }
struct EmptyHistoryView: View { let hotkey: String? }
struct NoResultsView: View { let query: String; let showSearchAll: Bool; let onClear: () -> Void; let onSearchAll: () -> Void }
struct PausedBar: View { let pausedUntil: Date?; let onResume: () -> Void }
```

**Behaviour:**
- Banner: 36 pt, `RoundedRectangle(8)` inset 8, fill `Color.yellow.opacity(0.15)`,
  `exclamationmark.triangle.fill` yellow, text `.callout`. Copy and actions per case:
  - `.accessibility` — "Allow Accessibility access so Clipjar can paste for you. Until then, ⏎ copies." +
    **Open Settings** → `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`
    and `SystemAccessibility().promptForTrust()` once per launch. Not dismissible.
  - `.recoveredFromCorruption` — "Your clip history was damaged and has been reset. The old file was kept in
    the Clipjar support folder." + **Show in Finder** (`NSWorkspace.shared.activateFileViewerSelecting([supportDir])`
    using `StoreOpener.defaultSupportDirectory()`) + ✕.
  - `.storageUnavailable` — "History can't be saved to disk this session." + ✕.
  - `.storageError` — "Couldn't save the last clip." (auto-hides via the model).
  - `.storageCorrupt` — "Clipjar's history database is damaged. Restart Clipjar to repair." + ✕.
  - `.pasteboardDenied` — "Clipjar can't read your clipboard. Allow it in System Settings ▸ Privacy & Security."
    + **Open Settings** → `x-apple.systempreferences:com.apple.preference.security`. Not dismissible.
  - `.appTranslocated` — "Move Clipjar to the Applications folder so permissions stick." Not dismissible.
  ✕ shown only when `banner.isDismissible`; buttons labelled by their text for VoiceOver.
- Toast: capsule `.regularMaterial`, `.callout`, padding 12×6, centred 12 pt above the footer, 120 ms fade
  (instant under Reduce Motion). `.deleted` → "Clip deleted · " + button **Undo ⌘Z** (`onUndo`);
  `.confirmPinnedDelete` → "Pinned — press ⌘⌫ again to delete". On appear post
  `AccessibilityNotification.Announcement(text).post()`.
- Empty history: `doc.on.clipboard` 36 pt `.tertiary`, "Your clipboard history is empty" `.title3`,
  "Copy something, then press \(hotkey) to find it here." or, when `hotkey == nil`, "Copy something, then
  click the Clipjar icon in the menu bar." `.callout` `.secondary`.
- No results: "No clips match “\(query)”" + borderless **Clear Search**; plus **Search All Types** when
  `showSearchAll`.
- Paused bar: `pause.circle` "Capture paused · Resumes at \(time)" (time `.formatted(date: .omitted, time:
  .shortened)`) or "Capture paused until you resume" + **Resume**.

**Verification:** `swift build`; `swift test`.
**Commit:** `git commit -m "feat(app): add banners, undo toast and empty states"`.

---

### Task 43: HistoryView composition (chrome, header, filter bar, footer)

**Requirements:** R55, R56, R57, R60, R63 (search/chip/gear labels), §6.1 layout, R41 (hint hidden without
hotkey), R2 (lazy list), R45 (search focused on open).
No assertable unit behaviour (SwiftUI layout).

**Files:**
- Modify: `Sources/Clipjar/Views/HistoryView.swift` (replace the temporary body)
- Create: `Sources/Clipjar/Views/VisualEffectBackground.swift`, `Sources/Clipjar/Views/FilterBar.swift`

**Interfaces — Produces:**
```swift
struct VisualEffectBackground: NSViewRepresentable { var material: NSVisualEffectView.Material = .popover }
    // blendingMode .behindWindow, state .active
struct FilterBar: View { @Bindable var model: HistoryViewModel }
struct HistoryView: View { let model: HistoryViewModel; let settings: SettingsStore }   // same signature as Task 39
```

**Behaviour:**
- Chrome (R55): `VisualEffectBackground` clipped to `RoundedRectangle(cornerRadius: 12, style:
  .continuous)`; 0.5 pt inner stroke `Color.primary.opacity(0.08)`; Increase Contrast → 1 pt
  `Color(nsColor: .separatorColor)` and an opaque `Color(nsColor: .windowBackgroundColor)` fill instead of
  the material. Fixed frame 720×460.
- Layout: header 52 → 1 px divider → banners (`ForEach(model.banners)`, `BannerView`) → chips 36 →
  `HStack { ClipListView (300) | Divider | PreviewView }` (or `EmptyHistoryView` / `NoResultsView`
  centred in the body when `model.isEmptyHistory` / `model.isNoResults`) → `PausedBar` when
  `settings.isPaused` → footer 28. `ToastView` overlaid 12 pt above the footer when `model.toast != nil`.
- Header (R56, horizontal padding 14): `magnifyingglass` 15 pt `.secondary`, 8 pt gap, plain `TextField`
  bound to `model.query`, `.title3`, prompt "Search clips…", `@FocusState` set true in `.onAppear` and in
  `.onChange(of: model.openGeneration)` (focus on every open), VoiceOver label "Search clips". Trailing: hotkey capsule (`HotkeyController.currentShortcutDescription`,
  `.caption` medium `.secondary`, padding 6×2, `RoundedRectangle(5)` fill `.quaternary`; hidden when nil),
  8 pt, gear button 28×28 borderless `gearshape` 14 pt → `model.handle(.openSettings)`, `.help("Settings (⌘,)")`,
  label "Settings".
- FilterBar (R57, padding 12, spacing 6): All `tray.full`, Text `text.alignleft`, Links `link`, Images
  `photo`, Files `doc`, 1×14 separator, Pinned `pin`. Chip = icon 11 pt + label `.callout` medium, padding
  10×4, `Capsule`; selected fill `accentColor.opacity(0.18)` + foreground `accentColor`; unselected
  `.secondary`, hover fill `.quaternary`. Tap sets `model.filter`. VoiceOver "Filter: Text, selected".
  Trailing `DisplayFormat.countLabel(model.matchCount)` `.caption` `.tertiary`.
- Footer (R60, padding 12): `DisplayFormat.footerHints(pasteOnSelect: settings.pasteOnSelect, trusted:
  !model.banners.contains(.accessibility), selectedPinned: <selected row isPinned>)` `.caption` `.tertiary`.

**Verification:** `swift build`; `swift test`.
**Commit:** `git commit -m "feat(app): compose the history panel with header, chips and footer"`.

---

### Task 44: Settings window and SettingsView

**Requirements:** R62, R42, R89 (confirmation UI), R53, §8 "SMAppService register/unregister throws",
"NSOpenPanel item without bundle id", R66 (unencrypted caption), R63 (keyboard reachable).
No assertable unit behaviour (SwiftUI/AppKit); retention logic tested in Task 29.

**Files:** Create `Sources/Clipjar/SettingsWindowController.swift`, `Sources/Clipjar/Views/SettingsView.swift`

**Interfaces — Produces:**
```swift
final class SettingsWindowController {
    init(settings: SettingsStore, store: ClipStore, retention: RetentionChanger)
    func show()     // NSApp.activate(); window.makeKeyAndOrderFront(nil); centred the first time only
}
struct SettingsView: View { let settings: SettingsStore; let store: ClipStore; let retention: RetentionChanger }
```

**Behaviour:**
- Window: `NSWindow` titled + closable, title "Clipjar Settings", width 480, height fits content
  (`NSHostingController` with `sizingOptions = .preferredContentSize`), `isReleasedWhenClosed = false`.
- `Form` `.formStyle(.grouped)` with `.keyboardShortcutsConflictPolicy(.init(menuItem: .block,
  systemShortcut: .block))`:
  - **General:** "Open Clipjar:" `KeyboardShortcuts.Recorder(for: .togglePanel, validateShortcut: { s in
    s.modifiers.isDisjoint(with: [.command, .option, .control]) ? .disallow("Use at least one of ⌘, ⌥ or ⌃.") : .allow })`
    + caption "Clear to use the menu bar icon only."; Toggle "Paste automatically after selecting"
    (`settings.pasteOnSelect`) + caption "Accessibility: Allowed ✓" or "Not allowed — " + **Open Settings**
    (Accessibility pane URL, as Task 42); Toggle "Launch at login" bound to `SMAppService.mainApp.status ==
    .enabled` (read on appear); toggling calls `register()`/`unregister()`; on throw revert the toggle and show
    the error's description as a caption; `.requiresApproval` → caption + button "Open Login Items" →
    `SMAppService.openSystemSettingsLoginItems()`.
  - **History:** Picker "Keep" (200 / 1,000 / 5,000 / 10,000 / Unlimited clips) and Picker "Remove clips
    older than" (Never / 1 day / 1 week / 30 days / 90 days / 1 year → 0/1/7/30/90/365), each bound to local
    `@State` seeded from settings; on change → `Task { switch try await retention.propose(limit:maxAgeDays:) {
    case .applied: break; case .needsConfirmation(let n): pending = (n, values) } }`;
    `.confirmationDialog("Remove \(n) older clips? Pinned clips are kept.")` [Remove → `retention.apply`]
    [Cancel → revert the local state to the settings value]. Caption "Pinned clips are never removed.".
    Button "Clear History…" (`role: .destructive`) → `.confirmationDialog("Clear all unpinned clips? This
    can't be undone.")` [Clear History → `try await store.clearAll(keepPinned: true)`] [Cancel].
  - **Privacy:** Toggle "Pause capture" (`isPaused` ↔ `pause(for: nil)`/`resume()`) + Button "Pause for 15
    minutes" (`pause(for: 900)`); "Ignored apps" list: icon + display name + bundle id `.caption`; `−`
    removes the selected id; `+` → `NSOpenPanel` at `/Applications`, `allowedContentTypes:
    [.applicationBundle]`, multiple selection, add each `Bundle(url:)?.bundleIdentifier` (skip nil, skip
    duplicates). Caption "Clipjar also skips anything apps mark as concealed, such as passwords. History is
    stored unencrypted on this Mac and never leaves it."
  - Footer: "Clipjar \(CFBundleShortVersionString) (\(CFBundleVersion))" `.caption` `.tertiary` (fallback
    "Clipjar dev" when running unbundled).

**Verification:** `swift build`; `swift test`.
**Commit:** `git commit -m "feat(app): add settings window with hotkey recorder and privacy controls"`.

---

### Task 45: Launch sequence, lifecycle and wiring **[complex]**

**Requirements:** R86 (order, A27 coalescing, A25 terminate), R30, R32 (prune triggers: launch, wake,
open), R34 (orphan cleanup), R35, R84 (events → banners), R85 (lock outcomes, `beginActivity`), R92, R93,
R47 (accessibility banner input), R39/R46 (Settings closes the panel first).
No new unit tests: the pieces (OpenGate, CaptureQueue, InstanceLock, StoreOpener, view model) are tested
in Tasks 14–35; this task wires them. Manual check in Task 49.

**Files:** Modify `Sources/Clipjar/AppDelegate.swift`

**Interfaces — Consumes:** everything listed in this part's header, plus `StatusItemController`,
`HotkeyController`, `PanelController`, `SettingsWindowController`.

**Behaviour — `applicationDidFinishLaunching` in this exact order:**
1. `NSApp.mainMenu = MainMenu.build(editActions:)`.
2. `supportDir = try? StoreOpener.defaultSupportDirectory()`; `InstanceLock.acquire(supportDirectory:)`:
   `.acquired(l)` → keep `l` for the process lifetime; `.heldByOther` → if
   `Bundle.main.bundleURL.pathExtension == "app"`: `DistributedNotificationCenter.default()
   .postNotificationName(.init(AppIdentity.showNotification), object: nil, userInfo: nil,
   deliverImmediately: true)` then `exit(0)`; otherwise use the in-memory store; `.failed(errno)` → log the
   errno, in-memory store (never exit).
3. `settings = SettingsStore(defaults: .standard)` (re-arms the pause timer).
4. `watcher = ClipboardWatcher(pasteboard: SystemPasteboard(), settings: { settings.filterSettings },
   frontmostApp: { NSWorkspace.shared.frontmostApplication.map { SourceApp(bundleID: $0.bundleIdentifier,
   name: $0.localizedName) } }, runningAppName: { NSRunningApplication.runningApplications(
   withBundleIdentifier: $0).first?.localizedName }, ownBundleID: AppIdentity.bundleID, sink: { c, s, d in
   captures.yield(CaptureItem(content: c, source: s, at: d)) })`; `onCapture` → `statusItem.pulse()`;
   `watcher.start()` (captures buffer in `captures` until step 6).
5. `StatusItemController(settings:onToggle: { requestOpen(.statusItem, toggle: true) }, onOpen: {
   requestOpen(.statusItem) }, onOpenSettings: openSettings)`; `HotkeyController { requestOpen(.cursor,
   toggle: true) }`; observers: `NSWorkspace.didActivateApplicationNotification` →
   `watcher.appActivated(SourceApp(from NSWorkspace.applicationUserInfoKey))`;
   `NSWorkspace.didWakeNotification` → `Task { try? await store?.prune(limit: settings.historyLimit,
   maxAgeDays: settings.maxAgeDays, now: Date()) }`; distributed `AppIdentity.showNotification` →
   `requestOpen(.centred)`. Observer closures hop with `MainActor.assumeIsolated` (queue `.main`).
   Capture activity: while `!settings.isPaused` hold `ProcessInfo.processInfo.beginActivity(options:
   .userInitiatedAllowingIdleSystemSleep, reason: "Clipboard capture")`; end it while paused (observation
   loop as in Task 37).
6. `Task { … }`: `result = supportDir != nil && lock acquired ? await StoreOpener.open(supportDirectory:) :
   StoreOpener.openInMemory()`; `await store.configure(limit:maxAgeDays:)` from settings; `try? await
   store.prune(…, now: Date())`; `captures.startConsuming(store:supportDirectory: result.supportDirectory,
   onEvent: { handle($0) })`; `Task.detached { _ = try? await store.cleanOrphanBlobs(now: Date()) }`.
7. Build `Paster(store:, pasteboard: SystemPasteboard(), ax: SystemAccessibility(), keys:
   SystemKeyPoster(), apps: SystemAppActivator(), sleep: { try? await Task.sleep(for: $0) })`,
   `HistoryViewModel(store:actions:)` with `HistoryActions(paste: { panel.paste(id: $0, copyOnly: $1) },
   close: { panel.hide() }, openSettings: openSettings, beep: { NSSound.beep() }, prune: { try? await
   store.prune(limit: settings.historyLimit, maxAgeDays: settings.maxAgeDays, now: Date()) },
   systemBanners: systemBanners, reportStoreError: { handle(StoreErrorClassifier.classify($0,
   supportDirectory: result.supportDirectory)) })`, `PanelController(model:settings:paster:
   statusButtonFrame: { statusItem.buttonScreenFrame })`; `model.setLaunchBanners(recovered:
   result.recoveredFromCorruption, storageUnavailable: result.storageUnavailable)`; flush events buffered
   before the model existed; `if let p = gate.markReady() { panel.show(p) }`.
8. If `!settings.hasLaunchedBefore` → set it, `requestOpen(.centred)`.

**Other members:**
- `requestOpen(_ p: OpenPlacement, toggle: Bool = false)`: if `toggle`, panel exists and is visible →
  `panel.hide()`; else `if let q = gate.request(p) { panel.show(q) }` (before step 7 requests coalesce
  into one, latest placement wins — A27).
- `systemBanners()`: `.accessibility` if `settings.pasteOnSelect && !AXIsProcessTrusted()`;
  `.pasteboardDenied` if `#available(macOS 15.4, *)` and `NSPasteboard.general.accessBehavior ==
  .alwaysDeny`; `.appTranslocated` if `Bundle.main.bundlePath.contains("/AppTranslocation/")`.
- `handle(_ e: StoreEvent)`: `model?.report(e)` or buffer until the model exists.
- `@objc func openSettings(_ sender: Any?)` (menu target) and `openSettings()`: `panel?.hide()` first, then
  lazily create `SettingsWindowController(settings:store:retention: RetentionChanger(store:settings:))` and `show()`.
- `applicationShouldHandleReopen(_:hasVisibleWindows:)` → `requestOpen(.centred)`; return `false`.
- `applicationWillTerminate`: `pending = model?.takePendingDeletionForTermination()`; `let sem =
  DispatchSemaphore(value: 0)`; `Task.detached { if let p = pending { _ = try? await store.delete(id: p.id,
  ifLastCopiedAt: p.lastCopiedAt) }; try? await store.scrubIfPending(); sem.signal() }`;
  `_ = sem.wait(timeout: .now() + 2)` (store work runs on the actor, never on main — no deadlock).

**Verification:** `swift build`; `swift test`; `swift run Clipjar` launches without crashing (status item
appears; hotkey/Recorder need the `.app` per R9 — checked in Task 49). Quit with the status menu.
**Commit:** `git commit -m "feat(app): wire launch sequence, capture pipeline and lifecycle"`.

---

### Task 46: Info.plist and Makefile app/sign/zip/install

**Requirements:** R9, R10, R11 (`app`, `sign`, `zip`, `install` rows), R12, R69, R70 (`make app` in CI), R4.
No assertable unit behaviour (packaging); verified by the commands below.

**Files:**
- Create: `Resources/Info.plist`
- Modify: `Makefile`, `.github/workflows/ci.yml` (add a `make app` step after `make test`)

**Behaviour:**
- `Resources/Info.plist` (XML plist) keys: `CFBundleIdentifier=com.vtrifonov.clipjar`,
  `CFBundleName=Clipjar`, `CFBundleDisplayName=Clipjar`, `CFBundleExecutable=Clipjar`,
  `CFBundlePackageType=APPL`, `CFBundleShortVersionString=0.0.0`, `CFBundleVersion=0` (both replaced by
  make), `LSMinimumSystemVersion=14.0`, `LSUIElement=true`, `NSPrincipalClass=NSApplication`,
  `LSApplicationCategoryType=public.app-category.productivity`, `NSAppSleepDisabled=true`,
  `NSHumanReadableCopyright="© 2026 Vasil Trifonov. MIT License."`. No entitlements file.
- Makefile targets (recipes TAB-indented; all paths via variables):
  - `app: build` → `rm -rf $(APP)`; `mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources`;
    `cp $(BIN_DIR)/Clipjar $(APP)/Contents/MacOS/Clipjar`; `cp -R $(BIN_DIR)/*.bundle $(APP)/Contents/Resources/`;
    `test -d $(APP)/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle`;
    `cp Resources/Info.plist $(APP)/Contents/Info.plist`;
    `plutil -replace CFBundleShortVersionString -string $(VERSION) $(APP)/Contents/Info.plist`;
    `plutil -replace CFBundleVersion -string $(BUILD_NUMBER) $(APP)/Contents/Info.plist`; universal check:
    print `lipo -archs` and fail unless it contains both `arm64` and `x86_64` (shell `case` in one recipe line).
  - `sign: app` → `codesign --force --deep -s - $(APP)`; `codesign --verify --deep --strict $(APP)`.
  - `zip: sign` → `rm -f build/Clipjar.zip`; `ditto -c -k --keepParent $(APP) build/Clipjar.zip`.
  - `install: sign` → `pkill -x Clipjar || true`; `rm -rf $(INSTALL_DIR)/Clipjar.app`;
    `ditto $(APP) $(INSTALL_DIR)/Clipjar.app`.

**Verification (each a separate command):** `make app` (prints `x86_64 arm64`); `plutil -lint
build/Clipjar.app/Contents/Info.plist`; `/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString"
build/Clipjar.app/Contents/Info.plist` → `0.1.0`; `make zip` (creates `build/Clipjar.zip`);
`codesign --verify --deep --strict build/Clipjar.app`; `make app VERSION=1.2.3` → plist shows `1.2.3`.
**Commit:** `git add Resources Makefile .github/workflows/ci.yml` →
`git commit -m "build: assemble, sign and zip a universal Clipjar.app"`.

---

### Task 47: Release workflow

**Requirements:** R71, R4. No assertable unit behaviour (CI config).

**Files:** Create `.github/workflows/release.yml`
```yaml
name: Release
on:
  push:
    tags: ['v*']
permissions:
  contents: write
env:
  XCODE_VERSION: "26.0"
jobs:
  release:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s "/Applications/Xcode_${XCODE_VERSION}.app"
      - run: swift --version
      - run: make test
      - name: Build Clipjar.zip
        run: make zip VERSION="${GITHUB_REF_NAME#v}" BUILD_NUMBER="${{ github.run_number }}"
      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh release create "$GITHUB_REF_NAME" build/Clipjar.zip --title "Clipjar $GITHUB_REF_NAME" --generate-notes
```
**Verification:** `yq '.jobs.release.steps | length' .github/workflows/release.yml` → `6`; `yq
'.permissions.contents' .github/workflows/release.yml` → `write`.
**Commit:** `git commit -m "ci: publish Clipjar.zip to GitHub Releases on version tags"`.

---

### Task 48: README

**Requirements:** R72, R66 (privacy statement), R68, R78 (record any scope cut), R79 (synthetic examples only).
No assertable unit behaviour (documentation).

**Files:** Modify `README.md` (keep the MIT licence section).

**Content (sections, in order):** what it is (one paragraph; screenshot added in Task 49); Features
(text/rich text, links, images, files; pins; preview; search with `@app` and `is:` tokens; type chips;
privacy controls; configurable hotkey); Keyboard map (the §6.3 table: ↑/↓, ⌘↑/⌘↓, Page Up/Down, ⏎,
⌥⏎, ⌘1–⌘9, ⌘P, ⌘⌫, ⌘Z, ⇥/⇧⇥, Esc, ⌘,, ⌘W); **Install** (download `Clipjar.zip` from Releases → unzip →
move to Applications **before first launch** (running from Downloads triggers App Translocation and breaks
permissions); first run: right-click ▸ **Open** ▸ **Open**, or on macOS 15+ System Settings ▸ Privacy &
Security ▸ **Open Anyway**; alternative `xattr -dr com.apple.quarantine /Applications/Clipjar.app`; it is
ad-hoc signed, not notarized); **Accessibility** (System Settings ▸ Privacy & Security ▸ Accessibility ▸
enable Clipjar; used only to post ⌘V; after an update remove Clipjar with "−" and re-add it, or run `tccutil
reset Accessibility com.vtrifonov.clipjar` and relaunch, because ad-hoc signatures change per build);
**Clipboard access** (macOS 15.4+ may ask — choose Always Allow; if denied, re-enable in Privacy &
Security); **Build from source** (Xcode with Swift ≥ 6.2; `make test`, `make install`); **Privacy**
(local only, no network, no analytics; unencrypted at rest; concealed/transient types skipped; ignore list;
excluded from Time Machine; deleted clips scrubbed from disk); **Data location**
(`~/Library/Application Support/Clipjar`; `*.corrupt-*` copies there may be deleted); **Uninstall** (quit,
delete the app and that folder); **License**. Examples use only synthetic values (`Hello, Clipjar`,
`https://example.com/docs`, `#FF8800`).

**Verification:** `rg -n '/Users/|\.internal' README.md` → no matches; render check by reading.
**Commit:** `git commit -m "docs: write README with install, permissions and privacy notes"`.

---

### Task 49: Smoke check, manual checklist and README screenshot

**Requirements:** R76, R75, R79, R9 (Recorder renders in the `.app`), R2 (open latency feel; 10k scroll).
Manual (GUI session required; run by the controller, not a unit-test task).

**Files:**
- Create: `scripts/window-id.swift` (prints the window number of the on-screen window owned by "Clipjar"
  with layer > 0, via `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)`;
  `kCGWindowOwnerName`, `kCGWindowLayer`, `kCGWindowNumber`)
- Create: `docs/images/clipjar-panel.png`
- Modify: `README.md` (add `![Clipjar panel](docs/images/clipjar-panel.png)` under the intro)

**Steps (one command per call):**
- [ ] `make clean`; `make test`; `make install`.
- [ ] `printf 'Hello, Clipjar' | pbcopy`; `open /Applications/Clipjar.app`.
- [ ] Clear history from Settings (confirm). Copy, one at a time: `printf 'Hello, Clipjar' | pbcopy`,
  `printf 'Second synthetic note' | pbcopy`, `printf 'func greet() { print("hi") }' | pbcopy`,
  `printf 'https://example.com/docs' | pbcopy`; a generated solid-colour PNG copied from Preview/TextEdit;
  one file under `/tmp` copied in Finder (R79: only TextEdit/Safari/Finder as sources).
- [ ] Press ⇧⌘V: rows, preview, search (`clip`, `@finder`, `is:link`), chips, ⌘P, ⌘⌫ + ⌘Z, Esc behave.
- [ ] `swift scripts/window-id.swift` → id; `screencapture -o -l <id> /tmp/clipjar-panel.png`; inspect the
  image for anything non-synthetic; copy to `docs/images/clipjar-panel.png`.
- [ ] Open Settings: the Recorder renders (proves the resource bundle, R9).
- [ ] R75 checklist (tick each): light/dark; Increase Contrast; Reduce Motion; real paste into
  TextEdit/Safari/Terminal; ⌘A/⌘C/⌘V/⌘X/⌘Z in the search field and Settings; ⌘W closes Settings; Japanese
  IME composition with ⏎/↑/↓/Esc; recorder: system-shortcut conflict blocked with previous value kept,
  ⇧-only rejected, clearing hides the hint; reopen from Finder opens the panel; first-run panel; launch at
  login; browser "Copy Image" captures an image; pasteboard Deny → banner (macOS 15.4+); App Translocation
  banner when run from Downloads; Gatekeeper first run from the zip on a second account.
- [ ] Commit: `git add scripts/window-id.swift docs/images/clipjar-panel.png README.md` →
  `git commit -m "docs: add smoke-checked panel screenshot"`.
