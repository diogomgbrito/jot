import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let store = NoteStore()
    let ui = UIState()
    let settings = AppSettings()
    private var panel: NotesPanel!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let icon = NSImage(named: "AppIcon") { NSApp.applicationIconImage = icon }
        buildPanel()
        NSApp.mainMenu = buildMainMenu()
        buildStatusItem()
        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()
        show()
    }

    func applicationWillTerminate(_ notification: Notification) { store.flush() }
    func applicationDidResignActive(_ notification: Notification) { store.flush() }

    /// Launching the already-running app (Raycast, Spotlight, Finder) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    private func applySettings() {
        panel.level = settings.floatOnTop ? .floating : .normal
        hotKey = nil
        settings.hotKeyError = nil
        guard settings.hotKeyEnabled else { return }
        let preset = HotKey.presets[settings.presetIndex]
        hotKey = HotKey(preset) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        if hotKey == nil {
            settings.hotKeyError = "Couldn't register \(preset.title); another app is probably using it."
        }
    }

    // MARK: Panel

    private func buildPanel() {
        panel = NotesPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 240)
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }
        let hosting = NSHostingView(rootView: RootView(store: store, ui: ui) { [weak self] in self?.hide() })
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        if !panel.setFrameUsingName("JotPanel") { panel.center() }
        panel.setFrameAutosaveName("JotPanel")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func toggle() {
        if NSApp.isActive && panel.isKeyWindow { hide() } else { show() }
    }

    func show() {
        store.reload()
        NSApp.unhide(nil)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        ui.focusEditor()
    }

    func hide() {
        store.flush()
        ui.showSwitcher = false
        panel.orderOut(nil)
        if settingsWindow?.isVisible != true { NSApp.hide(nil) }
    }

    // MARK: Settings

    @objc func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, store: store,
                                    chooseFolder: { [weak self] in self?.chooseFolder() },
                                    importNotes: { [weak self] in self?.importNotes(nil) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Jot Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.center()
            settingsWindow = window
        }
        NSApp.unhide(nil)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func chooseFolder() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.directoryURL = store.folder
        open.prompt = "Use Folder"
        open.message = "Choose the folder where Jot keeps its Markdown notes."
        let host = settingsWindow?.isVisible == true ? settingsWindow! : panel!
        open.beginSheetModal(for: host) { [weak self] response in
            guard response == .OK, let url = open.url else { return }
            self?.store.setFolder(url)
        }
    }

    @objc func importNotes(_ sender: Any?) {
        let open = NSOpenPanel()
        open.allowsMultipleSelection = true
        open.canChooseDirectories = false
        open.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        open.prompt = "Import"
        open.message = "Choose Markdown or text files to copy into Jot. The originals are left untouched."
        let host = settingsWindow?.isVisible == true ? settingsWindow! : panel!
        open.beginSheetModal(for: host) { [weak self] response in
            guard let self, response == .OK else { return }
            let count = self.store.importFiles(open.urls)
            let alert = NSAlert()
            alert.messageText = count == 0 ? "Nothing imported" : "Imported \(count) note\(count == 1 ? "" : "s")"
            if count == 0 { alert.informativeText = "The selected files were empty or not UTF-8 text." }
            alert.beginSheetModal(for: host)
        }
    }

    // MARK: Actions

    @objc func toggleAction(_ sender: Any?) { toggle() }
    @objc func hideAction(_ sender: Any?) { hide() }

    @objc func newNote(_ sender: Any?) {
        if !panel.isVisible { show() }
        ui.showSwitcher = false
        store.newNote()
        ui.focusEditor()
    }

    @objc func showSwitcher(_ sender: Any?) {
        if !panel.isKeyWindow { show() }
        ui.showSwitcher.toggle()
        if !ui.showSwitcher { ui.focusEditor() }
    }

    @objc func previousNote(_ sender: Any?) { store.cycle(-1); ui.focusEditor() }
    @objc func nextNote(_ sender: Any?) { store.cycle(1); ui.focusEditor() }
    @objc func deleteNote(_ sender: Any?) { store.deleteCurrent(); ui.focusEditor() }

    @objc func revealNote(_ sender: Any?) {
        store.flush()
        if let url = store.current?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAction(_:)) {
            item.title = panel.isVisible && NSApp.isActive ? "Hide Jot" : "Show Jot"
        }
        return true
    }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        it.target = target
        it.tag = tag
        return it
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem()
            holder.submenu = menu
            main.addItem(holder)
        }
        let find = NSTextFinder.Action.self
        submenu("Jot", [
            item("About Jot", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp),
            .separator(),
            item("Settings…", #selector(openSettings(_:)), ",", target: self),
            .separator(),
            item("Quit Jot", #selector(NSApplication.terminate(_:)), "q", target: NSApp),
        ])
        submenu("File", [
            item("New Note", #selector(newNote(_:)), "n", target: self),
            item("Find Note…", #selector(showSwitcher(_:)), "p", target: self),
            item("Previous Note", #selector(previousNote(_:)), "[", target: self),
            item("Next Note", #selector(nextNote(_:)), "]", target: self),
            .separator(),
            item("Import Markdown Files…", #selector(importNotes(_:)), "i", [.command, .shift], target: self),
            item("Reveal in Finder", #selector(revealNote(_:)), "r", [.command, .shift], target: self),
            item("Move to Trash", #selector(deleteNote(_:)), "\u{8}", [.command, .shift], target: self),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: find.showFindInterface.rawValue),
            item("Find Next", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: find.nextMatch.rawValue),
            item("Find Previous", #selector(NSTextView.performFindPanelAction(_:)), "g", [.command, .shift], tag: find.previousMatch.rawValue),
        ])
        submenu("Format", [
            item("Heading", #selector(MarkdownTextView.jotHeading(_:)), "h", [.command, .shift]),
            item("Bold", #selector(MarkdownTextView.jotBold(_:)), "b"),
            item("Italic", #selector(MarkdownTextView.jotItalic(_:)), "i"),
            item("Strikethrough", #selector(MarkdownTextView.jotStrikethrough(_:)), "x", [.command, .shift]),
            item("Inline Code", #selector(MarkdownTextView.jotCode(_:)), "c", [.command, .option]),
            item("Checklist", #selector(MarkdownTextView.jotChecklist(_:)), "l", [.command, .shift]),
        ])
        return main
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Jot")
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        guard NSApp.currentEvent?.type == .rightMouseUp else { return toggle() }
        let menu = NSMenu()
        [
            item("Show Jot", #selector(toggleAction(_:)), target: self),
            item("New Note", #selector(newNote(_:)), target: self),
            .separator(),
            item("Settings…", #selector(openSettings(_:)), target: self),
            .separator(),
            item("Quit Jot", #selector(NSApplication.terminate(_:)), target: NSApp),
        ].forEach(menu.addItem)
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }
}
