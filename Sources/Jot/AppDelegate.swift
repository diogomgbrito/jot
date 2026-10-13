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
    let shortcuts = ShortcutStore()
    private var panel: NotesPanel!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var shortcutItems: [(ShortcutID, NSMenuItem)] = []
    private var shortcutTips: [(ShortcutID, String, NSToolbarItem)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let icon = NSImage(named: "AppIcon") { NSApp.applicationIconImage = icon }
        buildPanel()
        NSApp.mainMenu = buildMainMenu()
        buildStatusItem()
        settings.onChange = { [weak self] in self?.applySettings() }
        shortcuts.onChange = { [weak self] in self?.applyShortcuts(); self?.applySettings() }
        shortcuts.onRecordingChange = { [weak self] in self?.applySettings() }
        applyShortcuts()
        applySettings()
        show()
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: CommandLine.arguments[i + 1])
        }
    }

    /// Debug aid: renders the panel (or, with `--settings <tab>`, the Settings window) to a PNG, then quits.
    private func snapshot(to path: String) {
        let args = CommandLine.arguments
        let tab = args.firstIndex(of: "--settings").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            if args.contains("--format-open") { UserDefaults.standard.set(true, forKey: "formatBarOpen") }
            if let tab {
                openSettings(nil)
                (settingsWindow?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = tab
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                let window: NSWindow? = tab == nil ? panel : settingsWindow
                guard let frameView = window?.contentView?.superview,
                      let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
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
        // Paused while recording so the current combo can be pressed into the recorder.
        guard settings.hotKeyEnabled, shortcuts.recordingID == nil else { return }
        guard let combo = shortcuts.combo(.toggleJot), let code = combo.keyCode else {
            settings.hotKeyError = "Record a shortcut to use it."
            return
        }
        hotKey = HotKey(keyCode: UInt32(code), modifiers: combo.carbonModifiers) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        if hotKey == nil {
            settings.hotKeyError = "Couldn't register \(combo.display); another app is probably using it."
        }
    }

    /// Pushes the current (possibly overridden) shortcuts into the menus and tooltips.
    private func applyShortcuts() {
        for (id, item) in shortcutItems {
            let combo = shortcuts.combo(id)
            item.keyEquivalent = combo?.key ?? ""
            item.keyEquivalentModifierMask = combo?.flags ?? []
        }
        for (id, tip, item) in shortcutTips { item.toolTip = tip + shortcuts.hint(id) }
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
        panel.titlebarSeparatorStyle = .none
        let toolbar = NSToolbar(identifier: "JotToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Self.titleItem]
        panel.toolbar = toolbar
        panel.toolbarStyle = .unified
        let hosting = NSHostingView(rootView: RootView(store: store, ui: ui, shortcuts: shortcuts) { [weak self] in self?.hide() })
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
            func tab<V: View>(_ label: String, _ symbol: String, _ view: V) -> NSTabViewItem {
                let host = NSHostingController(rootView: view)
                host.title = label
                host.sizingOptions = .preferredContentSize
                let item = NSTabViewItem(viewController: host)
                item.label = label
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
                return item
            }
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(tab("General", "gearshape", GeneralSettingsView(
                settings: settings, store: store,
                chooseFolder: { [weak self] in self?.chooseFolder() },
                importNotes: { [weak self] in self?.importNotes(nil) })))
            tabs.addTabViewItem(tab("Shortcuts", "keyboard", ShortcutSettingsView(settings: settings, shortcuts: shortcuts)))
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
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

    @objc func copyNote(_ sender: Any?) {
        guard let text = store.current?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

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

    private func item(_ title: String, _ action: Selector, target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = target
        it.tag = tag
        return it
    }

    /// A menu item whose title and keys come from the shortcut registry.
    private func item(_ id: ShortcutID, _ action: Selector, target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
        let it = item(id.title, action, target: target, tag: tag)
        shortcutItems.append((id, it))
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
            item(.settings, #selector(openSettings(_:)), target: self),
            .separator(),
            item(.quit, #selector(NSApplication.terminate(_:)), target: NSApp),
        ])
        submenu("File", [
            item(.newNote, #selector(newNote(_:)), target: self),
            item(.findNote, #selector(showSwitcher(_:)), target: self),
            item(.previousNote, #selector(previousNote(_:)), target: self),
            item(.nextNote, #selector(nextNote(_:)), target: self),
            .separator(),
            item(.copyNote, #selector(copyNote(_:)), target: self),
            item(.importNotes, #selector(importNotes(_:)), target: self),
            item(.reveal, #selector(revealNote(_:)), target: self),
            item(.trash, #selector(deleteNote(_:)), target: self),
            .separator(),
            item(.close, #selector(NSWindow.performClose(_:))),
        ])
        submenu("Edit", [
            item(.undo, Selector(("undo:"))),
            item(.redo, Selector(("redo:"))),
            .separator(),
            item(.cut, #selector(NSText.cut(_:))),
            item(.copy, #selector(NSText.copy(_:))),
            item(.paste, #selector(NSText.paste(_:))),
            item(.selectAll, #selector(NSText.selectAll(_:))),
            .separator(),
            item(.find, #selector(NSTextView.performFindPanelAction(_:)), tag: find.showFindInterface.rawValue),
            item(.findNext, #selector(NSTextView.performFindPanelAction(_:)), tag: find.nextMatch.rawValue),
            item(.findPrevious, #selector(NSTextView.performFindPanelAction(_:)), tag: find.previousMatch.rawValue),
        ])
        submenu("Format", [
            item(.heading1, #selector(MarkdownTextView.jotHeading1(_:))),
            item(.heading2, #selector(MarkdownTextView.jotHeading2(_:))),
            item(.heading3, #selector(MarkdownTextView.jotHeading3(_:))),
            item(.bodyText, #selector(MarkdownTextView.jotBodyText(_:))),
            item(.cycleHeading, #selector(MarkdownTextView.jotHeading(_:))),
            .separator(),
            item(.bold, #selector(MarkdownTextView.jotBold(_:))),
            item(.italic, #selector(MarkdownTextView.jotItalic(_:))),
            item(.strikethrough, #selector(MarkdownTextView.jotStrikethrough(_:))),
            item(.link, #selector(MarkdownTextView.jotLink(_:))),
            item(.inlineCode, #selector(MarkdownTextView.jotCode(_:))),
            item(.codeBlock, #selector(MarkdownTextView.jotCodeBlock(_:))),
            .separator(),
            item(.bulletList, #selector(MarkdownTextView.jotBulletList(_:))),
            item(.numberedList, #selector(MarkdownTextView.jotNumberedList(_:))),
            item(.checklist, #selector(MarkdownTextView.jotChecklist(_:))),
            item(.quote, #selector(MarkdownTextView.jotQuote(_:))),
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

// MARK: - Toolbar

extension AppDelegate: NSToolbarDelegate {
    static let titleItem = NSToolbarItem.Identifier("JotTitle")
    static let actionsItem = NSToolbarItem.Identifier("JotActions")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.titleItem, .flexibleSpace, Self.actionsItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.titleItem:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = NSHostingView(rootView: TitleView(store: store))
            return item
        case Self.actionsItem:
            let actions = NSMenuToolbarItem(itemIdentifier: NSToolbarItem.Identifier("JotActionsMenu"))
            actions.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Actions")
            actions.label = "Actions"
            actions.toolTip = "Actions"
            actions.showsIndicator = false
            let menu = NSMenu()
            [
                item("New Note", #selector(newNote(_:)), target: self),
                item("Find Note…", #selector(showSwitcher(_:)), target: self),
                .separator(),
                item("Copy Note as Markdown", #selector(copyNote(_:)), target: self),
                item("Reveal in Finder", #selector(revealNote(_:)), target: self),
                item("Import Markdown Files…", #selector(importNotes(_:)), target: self),
                .separator(),
                item("Move to Trash", #selector(deleteNote(_:)), target: self),
                .separator(),
                item("Settings…", #selector(openSettings(_:)), target: self),
            ].forEach(menu.addItem)
            actions.menu = menu

            let browse = toolbarButton("JotBrowse", "square.on.square", "Browse notes", .findNote, #selector(showSwitcher(_:)))
            let add = toolbarButton("JotNew", "plus", "New note", .newNote, #selector(newNote(_:)))
            let group = NSToolbarItemGroup(itemIdentifier: id)
            group.subitems = [actions, browse, add]
            group.controlRepresentation = .expanded
            group.selectionMode = .momentary
            return group
        default:
            return nil
        }
    }

    private func toolbarButton(_ id: String, _ symbol: String, _ tip: String, _ shortcut: ShortcutID,
                               _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier(id))
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        item.label = tip
        item.toolTip = tip + shortcuts.hint(shortcut)
        shortcutTips.append((shortcut, tip, item))
        item.target = self
        item.action = action
        return item
    }
}
