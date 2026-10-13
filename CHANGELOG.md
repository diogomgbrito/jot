# Changelog

All notable changes to Jot. Versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

### Fixed

- The character count no longer shows through the open formatting bar.

## [1.0.0] — 2026-10-13

First release.

### Added

- **Menu bar scratchpad.** A floating Markdown notes window that lives in the menu bar (no Dock icon). Left-click the icon to show or hide it, right-click for Settings and Quit. Launching Jot again (Raycast, Spotlight, Finder) brings the window up.
- **Unlimited notes as plain files.** Every note is a `.md` file in a folder you choose, so they work with Obsidian, iCloud Drive, git or any editor. Edits autosave; empty notes clean themselves up.
- **Live Markdown styling.** Headings, bold, italic, strikethrough, inline code, code blocks, links, quotes, rules, bulleted, numbered and task lists are styled as you type, with the syntax kept visible.
- **Raycast-style window.** Centred note title, an actions menu (⌘), note browser and new-note button in the toolbar, and a character count at the bottom.
- **Formatting bar.** The **T** button opens a bar with headings, text styles, link, code, code block, quote and list controls. Every action also has a shortcut in the Format menu.
- **Smart lists.** Return continues lists and checklists, Return on an empty item ends the list, Tab / ⇧Tab indent and outdent, and clicking `[ ]` ticks a task.
- **Quick switcher.** ⌘P searches note titles and content; Return on no match creates a note with that title. ⌘[ / ⌘] step through notes.
- **Settings.** Optional global shortcut (off by default, so you can bind Jot in Raycast instead), float on top, launch at login, notes folder.
- **Import.** Copy Markdown or text files into Jot, keeping their modification dates. Works with notes exported from Raycast Notes.
- **Homebrew cask.** `brew install --cask jot` from the `diogomgbrito/jot` tap. Universal build for Apple silicon and Intel, macOS 14 or later.

[1.0.0]: https://github.com/diogomgbrito/jot/releases/tag/v1.0.0
