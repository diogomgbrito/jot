import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key plus modifiers. `key` is an NSMenuItem key equivalent; `keyCode` is set for recorded
/// shortcuts (the global hotkey needs it).
struct KeyCombo: Codable, Equatable {
    var key: String
    var modifiers: UInt
    var keyCode: UInt16?

    init(_ key: String, _ mods: NSEvent.ModifierFlags = .command, keyCode: Int? = nil) {
        self.key = key
        self.modifiers = mods.rawValue
        self.keyCode = keyCode.map(UInt16.init)
    }

    init?(event e: NSEvent) {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let key: String
        switch Int(e.keyCode) {
        case kVK_Delete: key = "\u{8}"
        case kVK_ForwardDelete: key = Self.fn(NSDeleteFunctionKey)
        case kVK_Return, kVK_ANSI_KeypadEnter: key = "\r"
        case kVK_Tab: key = "\t"
        case kVK_Space: key = " "
        case kVK_Escape: key = "\u{1b}"
        default:
            guard let c = e.characters(byApplyingModifiers: []), !c.isEmpty else { return nil }
            key = c.lowercased()
        }
        self.init(key, mods, keyCode: Int(e.keyCode))
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var display: String {
        let f = flags
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        if let name = Self.names[key] { return s + name }
        if isFunctionKey, let u = key.unicodeScalars.first?.value { return s + "F\(u - 0xF704 + 1)" }
        return s + key.uppercased()
    }

    var carbonModifiers: UInt32 {
        let f = flags
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        if f.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }

    var isFunctionKey: Bool {
        guard let u = key.unicodeScalars.first?.value else { return false }
        return (0xF704...0xF726).contains(u)
    }

    /// Menu shortcuts need ⌘ or ⌃ so they don't swallow typing; the global one needs ⌘, ⌥ or ⌃.
    func isValid(global: Bool) -> Bool {
        if isFunctionKey { return true }
        let required: NSEvent.ModifierFlags = global ? [.command, .option, .control] : [.command, .control]
        return !flags.intersection(required).isEmpty
    }

    func sameKeys(as other: KeyCombo) -> Bool {
        key.lowercased() == other.key.lowercased() && modifiers == other.modifiers
    }

    private static func fn(_ v: Int) -> String { String(Character(UnicodeScalar(UInt32(v))!)) }

    private static let names: [String: String] = [
        "\u{8}": "⌫", fn(NSDeleteFunctionKey): "⌦", "\r": "↩", "\t": "⇥", " ": "Space", "\u{1b}": "⎋",
        fn(NSUpArrowFunctionKey): "↑", fn(NSDownArrowFunctionKey): "↓",
        fn(NSLeftArrowFunctionKey): "←", fn(NSRightArrowFunctionKey): "→",
        fn(NSHomeFunctionKey): "↖", fn(NSEndFunctionKey): "↘",
        fn(NSPageUpFunctionKey): "⇞", fn(NSPageDownFunctionKey): "⇟",
    ]
}

/// Every command that can have a shortcut, with its menu title and default keys.
enum ShortcutID: String, CaseIterable, Identifiable {
    case toggleJot
    case settings, quit
    case newNote, findNote, previousNote, nextNote, copyNote, importNotes, reveal, trash, close
    case undo, redo, cut, copy, paste, selectAll, find, findNext, findPrevious
    case heading1, heading2, heading3, bodyText, cycleHeading
    case bold, italic, strikethrough, link, inlineCode, codeBlock
    case bulletList, numberedList, checklist, quote

    var id: String { rawValue }
    var group: String { spec.group }
    var title: String { spec.title }
    var defaultCombo: KeyCombo? { spec.combo }

    static let groups = ["Global", "Jot", "File", "Edit", "Format"]

    private var spec: (group: String, title: String, combo: KeyCombo?) {
        let s: NSEvent.ModifierFlags = [.command, .shift]
        let o: NSEvent.ModifierFlags = [.command, .option]
        switch self {
        case .toggleJot: return ("Global", "Show / Hide Jot", KeyCombo("n", o, keyCode: kVK_ANSI_N))
        case .settings: return ("Jot", "Settings…", KeyCombo(","))
        case .quit: return ("Jot", "Quit Jot", KeyCombo("q"))
        case .newNote: return ("File", "New Note", KeyCombo("n"))
        case .findNote: return ("File", "Find Note…", KeyCombo("p"))
        case .previousNote: return ("File", "Previous Note", KeyCombo("["))
        case .nextNote: return ("File", "Next Note", KeyCombo("]"))
        case .copyNote: return ("File", "Copy Note as Markdown", nil)
        case .importNotes: return ("File", "Import Markdown Files…", KeyCombo("i", s))
        case .reveal: return ("File", "Reveal in Finder", KeyCombo("r", s))
        case .trash: return ("File", "Move to Trash", KeyCombo("\u{8}", s))
        case .close: return ("File", "Close", KeyCombo("w"))
        case .undo: return ("Edit", "Undo", KeyCombo("z"))
        case .redo: return ("Edit", "Redo", KeyCombo("z", s))
        case .cut: return ("Edit", "Cut", KeyCombo("x"))
        case .copy: return ("Edit", "Copy", KeyCombo("c"))
        case .paste: return ("Edit", "Paste", KeyCombo("v"))
        case .selectAll: return ("Edit", "Select All", KeyCombo("a"))
        case .find: return ("Edit", "Find…", KeyCombo("f"))
        case .findNext: return ("Edit", "Find Next", KeyCombo("g"))
        case .findPrevious: return ("Edit", "Find Previous", KeyCombo("g", s))
        case .heading1: return ("Format", "Heading 1", KeyCombo("1", o))
        case .heading2: return ("Format", "Heading 2", KeyCombo("2", o))
        case .heading3: return ("Format", "Heading 3", KeyCombo("3", o))
        case .bodyText: return ("Format", "Body Text", KeyCombo("0", o))
        case .cycleHeading: return ("Format", "Cycle Heading", KeyCombo("h", s))
        case .bold: return ("Format", "Bold", KeyCombo("b"))
        case .italic: return ("Format", "Italic", KeyCombo("i"))
        case .strikethrough: return ("Format", "Strikethrough", KeyCombo("x", s))
        case .link: return ("Format", "Link", KeyCombo("k"))
        case .inlineCode: return ("Format", "Inline Code", KeyCombo("c", o))
        case .codeBlock: return ("Format", "Code Block", KeyCombo("c", [.command, .option, .shift]))
        case .bulletList: return ("Format", "Bulleted List", KeyCombo("8", s))
        case .numberedList: return ("Format", "Numbered List", KeyCombo("7", s))
        case .checklist: return ("Format", "Checklist", KeyCombo("l", s))
        case .quote: return ("Format", "Quote", KeyCombo("'", s))
        }
    }
}

/// User overrides of the default shortcuts, persisted in UserDefaults, plus the recorder state.
@MainActor
final class ShortcutStore: ObservableObject {
    /// An override with an empty key means "no shortcut".
    @Published private var overrides: [String: KeyCombo] = [:]
    @Published private(set) var recordingID: ShortcutID?
    var onChange: (() -> Void)?
    var onRecordingChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private var monitor: Any?

    init() {
        if let data = defaults.data(forKey: "shortcuts"),
           let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            overrides = saved
        }
        migrateHotKeyPreset()
    }

    func combo(_ id: ShortcutID) -> KeyCombo? {
        guard let o = overrides[id.rawValue] else { return id.defaultCombo }
        return o.key.isEmpty ? nil : o
    }

    func isCustom(_ id: ShortcutID) -> Bool { overrides[id.rawValue] != nil }
    var hasOverrides: Bool { !overrides.isEmpty }

    /// " (⌘K)" for tooltips, or "" when the command has no shortcut.
    func hint(_ id: ShortcutID) -> String { combo(id).map { " (\($0.display))" } ?? "" }

    func set(_ combo: KeyCombo?, for id: ShortcutID) {
        let d = id.defaultCombo
        switch (combo, d) {
        case (nil, nil): overrides[id.rawValue] = nil
        case let (c?, d?) where c.sameKeys(as: d): overrides[id.rawValue] = nil
        default: overrides[id.rawValue] = combo ?? KeyCombo("", [])
        }
        save()
    }

    func reset(_ id: ShortcutID) { overrides[id.rawValue] = nil; save() }
    func resetAll() { overrides = [:]; save() }

    /// Another command that uses the same keys, if any.
    func conflict(for id: ShortcutID) -> ShortcutID? {
        guard let c = combo(id) else { return nil }
        return ShortcutID.allCases.first { $0 != id && combo($0)?.sameKeys(as: c) == true }
    }

    // MARK: Recording

    func startRecording(_ id: ShortcutID) {
        stopRecording()
        recordingID = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
            return nil
        }
        onRecordingChange?()
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recordingID != nil else { return }
        recordingID = nil
        onRecordingChange?()
    }

    private func record(_ e: NSEvent) {
        guard let id = recordingID else { return }
        let plain = e.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if plain && Int(e.keyCode) == kVK_Escape { return stopRecording() }
        if plain && [kVK_Delete, kVK_ForwardDelete].contains(Int(e.keyCode)) {
            set(nil, for: id)
            return stopRecording()
        }
        guard let combo = KeyCombo(event: e), combo.isValid(global: id == .toggleJot) else { return NSSound.beep() }
        set(combo, for: id)
        stopRecording()
    }

    private func save() {
        if overrides.isEmpty { defaults.removeObject(forKey: "shortcuts") }
        else if let data = try? JSONEncoder().encode(overrides) { defaults.set(data, forKey: "shortcuts") }
        onChange?()
    }

    /// 1.0 offered five fixed global shortcuts; carry a non-default choice over.
    private func migrateHotKeyPreset() {
        guard let i = defaults.object(forKey: "hotKeyPreset") as? Int else { return }
        defaults.removeObject(forKey: "hotKeyPreset")
        let legacy = [
            KeyCombo("n", [.command, .option], keyCode: kVK_ANSI_N),
            KeyCombo("n", [.control, .option], keyCode: kVK_ANSI_N),
            KeyCombo("n", [.control, .option, .command], keyCode: kVK_ANSI_N),
            KeyCombo(" ", [.option], keyCode: kVK_Space),
            KeyCombo(" ", [.control, .option], keyCode: kVK_Space),
        ]
        guard i > 0, i < legacy.count, overrides[ShortcutID.toggleJot.rawValue] == nil else { return }
        overrides[ShortcutID.toggleJot.rawValue] = legacy[i]
        if let data = try? JSONEncoder().encode(overrides) { defaults.set(data, forKey: "shortcuts") }
    }
}

// MARK: - Settings page

struct ShortcutSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shortcuts: ShortcutStore

    var body: some View {
        Form {
            Section {
                Toggle("Show / hide Jot from anywhere", isOn: $settings.hotKeyEnabled)
                row(.toggleJot, title: "Shortcut").disabled(!settings.hotKeyEnabled)
                if let error = settings.hotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Global")
            } footer: {
                Text("Leave this off if you open Jot with a Raycast hotkey.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(ShortcutID.groups.dropFirst(), id: \.self) { group in
                Section(group) {
                    ForEach(ShortcutID.allCases.filter { $0.group == group }) { row($0) }
                }
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Click a shortcut, then press the new keys. ⌫ removes it, Esc cancels. Esc always hides Jot.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { shortcuts.resetAll() }
                        .disabled(!shortcuts.hasOverrides)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onDisappear { shortcuts.stopRecording() }
    }

    private func row(_ id: ShortcutID, title: String? = nil) -> some View {
        LabeledContent {
            ShortcutField(store: shortcuts, id: id)
        } label: {
            Text(title ?? id.title)
            if let other = shortcuts.conflict(for: id) {
                Text("Also used by \(other.title)").foregroundStyle(.orange)
            }
        }
    }
}

/// Click to record; shows the current keys and a reset button when overridden.
struct ShortcutField: View {
    @ObservedObject var store: ShortcutStore
    let id: ShortcutID

    var body: some View {
        let recording = store.recordingID == id
        let combo = store.combo(id)
        HStack(spacing: 4) {
            Button {
                recording ? store.stopRecording() : store.startRecording(id)
            } label: {
                Text(recording ? "Press keys…" : combo?.display ?? "None")
                    .foregroundStyle(recording ? AnyShapeStyle(.tint) : combo == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .frame(minWidth: 84)
            }
            .help(recording ? "Press the new shortcut, ⌫ to remove, Esc to cancel" : "Click to change")

            Button { store.reset(id) } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Restore default (\(id.defaultCombo?.display ?? "none"))")
            .opacity(store.isCustom(id) ? 1 : 0)
            .disabled(!store.isCustom(id))
        }
    }
}
