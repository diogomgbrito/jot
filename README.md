# Jot

A tiny native macOS replacement for Raycast Notes: a floating Markdown scratchpad behind a global hotkey, with unlimited notes stored as plain `.md` files.

## Install

```sh
./scripts/bundle.sh --install   # builds, copies to ~/Applications/Jot.app, launches
```

Jot lives in the menu bar (no Dock icon). Left-click the icon to toggle, right-click for Settings (also ⌘,).
Launching Jot while it's running (Raycast hotkey, Spotlight, Finder) shows the window.

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
| ⌘B / ⌘I / ⇧⌘X / ⌥⌘C | Bold / italic / strikethrough / inline code |
| ⇧⌘H | Cycle heading level |
| ⇧⌘L | Toggle checklist item |
| Tab / ⇧Tab | Indent / outdent list item |

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
