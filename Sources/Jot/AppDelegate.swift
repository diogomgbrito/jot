import AppKit
import ServiceManagement
import SwiftUI

final class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let store = NoteStore()
    let ui = UIState()
    private var panel: NotesPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private let defaults = UserDefaults.standard

    private var presetIndex: Int {
        get { min(defaults.integer(forKey: "hotKeyPreset"), HotKey.presets.count - 1) }
        set { defaults.set(newValue, forKey: "hotKeyPreset") }
    }

    private var floatsOnTop: Bool {
        get { defaults.object(forKey: "floatOnTop") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "floatOnTop") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        NSApp.mainMenu = buildMainMenu()
        buildStatusItem()
        registerHotKey()
        show()
    }

    func applicationWillTerminate(_ notification: Notification) { store.flush() }
    func applicationDidResignActive(_ notification: Notification) { store.flush() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
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
        panel.level = floatsOnTop ? .floating : .normal
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

    func windowWillClose(_ notification: Notification) { store.flush() }

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
        NSApp.hide(nil)
    }

    // MARK: Hotkey

    private func registerHotKey() {
        hotKey = nil
        let preset = HotKey.presets[presetIndex]
        hotKey = HotKey(preset) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        if hotKey == nil {
            let alert = NSAlert()
            alert.messageText = "Couldn't register \(preset.title)"
            alert.informativeText = "Another app is probably using it. Pick a different hotkey from the menu bar icon."
            alert.runModal()
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

    @objc func openFolder(_ sender: Any?) { NSWorkspace.shared.open(store.folder) }

    @objc func chooseFolder(_ sender: Any?) {
        if !panel.isVisible { show() }
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.directoryURL = store.folder
        open.prompt = "Use Folder"
        open.message = "Choose the folder where Jot keeps its Markdown notes."
        open.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = open.url else { return }
            self?.store.setFolder(url)
        }
    }

    @objc func choosePreset(_ sender: NSMenuItem) {
        presetIndex = sender.tag
        registerHotKey()
    }

    @objc func toggleFloat(_ sender: Any?) {
        floatsOnTop.toggle()
        panel.level = floatsOnTop ? .floating : .normal
    }

    @objc func toggleLoginItem(_ sender: Any?) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(choosePreset(_:)): item.state = item.tag == presetIndex ? .on : .off
        case #selector(toggleFloat(_:)): item.state = floatsOnTop ? .on : .off
        case #selector(toggleLoginItem(_:)): item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        case #selector(toggleAction(_:)): item.title = panel.isVisible && NSApp.isActive ? "Hide Jot" : "Show Jot"
        default: break
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

    private func settingsItems() -> [NSMenuItem] {
        let hotkeys = NSMenu()
        for (i, p) in HotKey.presets.enumerated() {
            hotkeys.addItem(item(p.title, #selector(choosePreset(_:)), target: self, tag: i))
        }
        let hotkeyItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        hotkeyItem.submenu = hotkeys
        return [
            item("Choose Notes Folder…", #selector(chooseFolder(_:)), target: self),
            item("Open Notes Folder", #selector(openFolder(_:)), target: self),
            hotkeyItem,
            item("Float on Top", #selector(toggleFloat(_:)), target: self),
            item("Launch at Login", #selector(toggleLoginItem(_:)), target: self),
        ]
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
        ] + settingsItems() + [
            .separator(),
            item("Quit Jot", #selector(NSApplication.terminate(_:)), "q", target: NSApp),
        ])
        submenu("File", [
            item("New Note", #selector(newNote(_:)), "n", target: self),
            item("Find Note…", #selector(showSwitcher(_:)), "p", target: self),
            item("Previous Note", #selector(previousNote(_:)), "[", target: self),
            item("Next Note", #selector(nextNote(_:)), "]", target: self),
            .separator(),
            item("Reveal in Finder", #selector(revealNote(_:)), "r", [.command, .shift], target: self),
            item("Move to Trash", #selector(deleteNote(_:)), "\u{8}", [.command, .shift], target: self),
            .separator(),
            item("Hide", #selector(hideAction(_:)), "w", target: self),
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
        ([
            item("Show Jot", #selector(toggleAction(_:)), target: self),
            item("New Note", #selector(newNote(_:)), target: self),
            .separator(),
        ] + settingsItems() + [
            .separator(),
            item("Quit Jot", #selector(NSApplication.terminate(_:)), target: NSApp),
        ]).forEach(menu.addItem)
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }
}
