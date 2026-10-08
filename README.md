# Clipjar

Clipjar is a fast, keyboard-first clipboard history manager that lives in the macOS menu bar. Press a
hotkey, type a few letters, press Return, and the clip is pasted straight into the app you were using. Your history
stays on your Mac: Clipjar has no network code, no accounts and no analytics.

Requires macOS 14 or later, on Apple silicon or Intel.

## Features

- **Everything you copy:** plain and rich text, links, images and files from Finder.
- **Pins:** keep clips you reuse at hand. Pinned clips are never pruned.
- **Preview:** see the whole text, the full-size image or the file list before you paste.
- **Search as you type:** use quotes for an exact phrase (`"Hello, Clipjar"`), `@app` to limit results to clips
  copied from one app (`@Safari example.com`), and `is:text`, `is:link`, `is:image`, `is:file` or `is:pinned` to
  filter by type.
- **Type chips:** All, Text, Links, Images, Files and Pinned. Press ⇥ to cycle through them.
- **Privacy controls:** pause capture (indefinitely or for 15 minutes), ignore specific apps, and skip anything
  apps mark as concealed, such as passwords.
- **Configurable hotkey:** ⇧⌘V by default. Change or clear it in Settings.

## Keyboard map

| Key | Action |
| --- | --- |
| ↑ / ↓ | Select the previous / next clip |
| ⌘↑ / ⌘↓ | Jump to the first / last clip |
| Page Up / Page Down | Move up / down by a page |
| ⏎ | Paste the selected clip (copies it when pasting is off or not allowed) |
| ⌥⏎ | Copy the selected clip without pasting |
| ⌘1 – ⌘9 | Paste clip 1–9 |
| ⌘P | Pin or unpin the selected clip |
| ⌘⌫ | Delete the selected clip (press twice for a pinned clip) |
| ⌘Z | Undo the last delete, while its notice is showing |
| ⇥ / ⇧⇥ | Next / previous type chip |
| Esc | Clear the search, then close the panel |
| ⌘, | Open Settings |
| ⌘W | Close the panel |

## Install

1. Download `Clipjar.zip` from the [Releases](../../releases) page and unzip it.
2. Move `Clipjar.app` to your Applications folder **before you open it for the first time**. When an app runs
   straight from Downloads, macOS runs it from a randomised read-only location (App Translocation), and the
   permissions you grant it don't stick.
3. Open it the first time:
   - right-click `Clipjar.app` ▸ **Open**, then click **Open** again; or
   - on macOS 15 and later, open it once, then go to System Settings ▸ Privacy & Security and click
     **Open Anyway**; or
   - in Terminal: `xattr -dr com.apple.quarantine /Applications/Clipjar.app`

Clipjar is ad-hoc signed, not notarized, so macOS asks you to confirm the first launch.

## Accessibility

To paste for you, Clipjar needs Accessibility access: System Settings ▸ Privacy & Security ▸ Accessibility ▸ turn
on Clipjar. Clipjar uses it only to send ⌘V to the app you were using. Without it, Return copies the clip and you
paste it yourself.

Each build is signed ad hoc, so after an update macOS no longer recognises the old permission. Select Clipjar in
the Accessibility list, remove it with **−**, and add it again. Or run this and relaunch Clipjar:

```sh
tccutil reset Accessibility com.vtrifonov.clipjar
```

## Clipboard access

On macOS 15.4 and later, macOS may ask whether Clipjar can read the clipboard. Choose **Always Allow**. If you
denied it, turn it back on in System Settings ▸ Privacy & Security; Clipjar shows a notice until you do.

## Build from source

You need Xcode with Swift 6.2 or later.

```sh
make test      # run the test suite
make install   # build, sign and copy Clipjar.app to /Applications
```

`make app` builds a universal `build/Clipjar.app`, and `make zip` packages it as `build/Clipjar.zip`.

## Privacy

- Everything stays on this Mac. Clipjar has no network code and no analytics.
- History is stored unencrypted on disk, readable only by your user account.
- Content that apps mark as concealed or transient (for example, passwords from password managers) is never saved.
- Apps on the ignore list are never captured. Common password managers are on it by default.
- The history folder is excluded from Time Machine backups.
- Deleted clips are scrubbed from the database file, not just hidden.

## Data location

History lives in `~/Library/Application Support/Clipjar`. If the database is ever damaged, Clipjar starts with a
fresh history and keeps the old file there with `.corrupt-` in its name. You can delete those copies.

## Uninstall

Quit Clipjar from its menu bar icon, delete `Clipjar.app` from Applications, then delete
`~/Library/Application Support/Clipjar`.

## License

MIT — see [LICENSE](LICENSE).
