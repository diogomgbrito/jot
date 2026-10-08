import ServiceManagement
import SwiftUI

/// User preferences, persisted in UserDefaults. `onChange` lets the app delegate re-apply them.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?

    @Published var hotKeyEnabled: Bool {
        didSet { defaults.set(hotKeyEnabled, forKey: "hotKeyEnabled"); onChange?() }
    }
    @Published var presetIndex: Int {
        didSet { defaults.set(presetIndex, forKey: "hotKeyPreset"); onChange?() }
    }
    @Published var floatOnTop: Bool {
        didSet { defaults.set(floatOnTop, forKey: "floatOnTop"); onChange?() }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLoginItem() }
    }
    @Published var hotKeyError: String?
    @Published var loginItemError: String?

    init() {
        hotKeyEnabled = defaults.object(forKey: "hotKeyEnabled") as? Bool ?? false
        presetIndex = min(defaults.integer(forKey: "hotKeyPreset"), HotKey.presets.count - 1)
        floatOnTop = defaults.object(forKey: "floatOnTop") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLoginItem() {
        let service = SMAppService.mainApp
        guard launchAtLogin != (service.status == .enabled) else { return }
        do {
            if launchAtLogin { try service.register() } else { try service.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            launchAtLogin = service.status == .enabled
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: NoteStore
    let chooseFolder: () -> Void
    let importNotes: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Global shortcut to show / hide Jot", isOn: $settings.hotKeyEnabled)
                Picker("Shortcut", selection: $settings.presetIndex) {
                    ForEach(HotKey.presets.indices, id: \.self) { i in
                        Text(HotKey.presets[i].title).tag(i)
                    }
                }
                .disabled(!settings.hotKeyEnabled)
                if let error = settings.hotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Leave this off if you open Jot with a Raycast hotkey.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Window") {
                Toggle("Float on top of other windows", isOn: $settings.floatOnTop)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Storage") {
                LabeledContent("Notes folder") {
                    Text(store.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Choose…", action: chooseFolder)
                    Button("Open in Finder") { NSWorkspace.shared.open(store.folder) }
                }
            }

            Section {
                Button("Import Markdown Files…", action: importNotes)
            } header: {
                Text("Import")
            } footer: {
                Text("To bring notes over from Raycast: in Raycast Notes, open each note's actions (⌘K) and export it as Markdown, then import the files here. Raycast keeps its copies.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}
