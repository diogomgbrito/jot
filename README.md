# Jot

A tiny native macOS replacement for Raycast Notes: a floating Markdown scratchpad behind a global hotkey, with unlimited notes stored as plain `.md` files.

## Install

```sh
brew tap diogomgbrito/jot https://github.com/diogomgbrito/jot
brew trust diogomgbrito/jot
brew install --cask jot
```

Update with `brew upgrade --cask jot`.

> The app is not notarized by Apple. The Homebrew cask removes the quarantine flag so macOS lets it open.

From source: `./scripts/bundle.sh --install` builds, copies to `~/Applications/Jot.app` and launches. See [RELEASING.md](RELEASING.md) to publish a version.

Jot lives in the menu bar (no Dock icon). Left-click the icon to toggle, right-click for Settings (also ⌘,).
Launching Jot while it's running (Raycast hotkey, Spotlight, Finder) shows the window.

Debug: `.build/debug/Jot --snapshot out.png [--format-open]` renders the window to a PNG and quits.

Settings: optional global shortcut (off by default), float on top, launch at login, notes folder, import.

## Shortcuts

| Keys | Action |
| --- | --- |
| Esc / ⌘W / ✕ | Hide |
| Global shortcut (enable in Settings) | Show / hide Jot from anywhere |
| ⌘N | New note |
| ⌘P | Search / switch notes (↩ on no match creates one) |
| ⌘[ / ⌘] | Previous / next note |
| ⇧⌘⌫ | Move note to Trash |
| ⇧⌘R | Reveal note in Finder |
| ⇧⌘I | Import Markdown files |
| ⌘F | Find in note |
| ⌘B / ⌘I / ⇧⌘X / ⌘K | Bold / italic / strikethrough / link |
| ⌥⌘C / ⌥⇧⌘C | Inline code / code block |
| ⌥⌘1–3 / ⌥⌘0 / ⇧⌘H | Heading 1–3 / body text / cycle heading |
| ⇧⌘8 / ⇧⌘7 / ⇧⌘L / ⇧⌘' | Bulleted / numbered / checklist / quote (toggles, multi-line) |
| Tab / ⇧Tab | Indent / outdent list item |

The **T** button (bottom-right) opens a formatting bar; the top bar has an actions menu (⌘), browse and new note.
Click a `[ ]` to tick it. Return continues lists, numbered lists and checklists; Return on an empty item ends the list.

## Storage

Notes are Markdown files in `~/Notes` (change with **Choose Notes Folder…**; an iCloud Drive folder gives you sync).
Filenames are creation timestamps; the title is the first line. Empty notes are deleted when you switch away.
Edits autosave after 400 ms and on hide/quit. Files edited elsewhere are picked up when Jot is shown.

## Importing from Raycast Notes

Raycast's database is encrypted, so Jot can't read it directly. In Raycast Notes, open each note's actions (⌘K) and
export it as Markdown, then use **Import Markdown Files…** (⇧⌘I or Settings). Files are copied; Raycast keeps its notes.

## Layout

- `Sources/Jot/AppDelegate.swift` — panel, menus, status item, hotkey wiring
- `Sources/Jot/NoteStore.swift` — file-backed notes model
- `Sources/Jot/Editor.swift` — NSTextView wrapper, Markdown highlighter, editing behaviours
- `Sources/Jot/Views.swift` — SwiftUI header, footer, note switcher
- `Sources/Jot/Settings.swift` — preferences model and Settings window
- `Sources/Jot/HotKey.swift` — Carbon global hotkey
- `scripts/make-icon.swift` — regenerates `Resources/AppIcon.icns`
- `scripts/release.sh` — universal DMG for a release; `Casks/jot.rb` — Homebrew cask
