import AppKit
import SwiftUI

@MainActor
final class UIState: ObservableObject {
    @Published var showSwitcher = false
    weak var textView: NSTextView?

    func focusEditor() {
        DispatchQueue.main.async { [weak self] in
            guard let tv = self?.textView else { return }
            tv.window?.makeFirstResponder(tv)
        }
    }
}

struct RootView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: UIState
    let onEscape: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                MarkdownEditor(
                    text: Binding(get: { store.current?.text ?? "" }, set: { store.updateCurrent($0) }),
                    noteID: store.currentID,
                    ui: ui,
                    onEscape: onEscape)
                footer
            }
            if ui.showSwitcher {
                Color.black.opacity(0.08)
                    .contentShape(Rectangle())
                    .onTapGesture { ui.showSwitcher = false; ui.focusEditor() }
                SwitcherView(store: store, ui: ui)
                    .padding(.top, 34)
            }
        }
        .background(VisualEffectBackground())
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 44, height: 1)
            Spacer(minLength: 0)
            Text(store.current?.title ?? "Jot")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { ui.showSwitcher.toggle() } label: { Image(systemName: "list.bullet") }
                .help("Browse notes (⌘P)")
            Button { store.newNote(); ui.focusEditor() } label: { Image(systemName: "square.and.pencil") }
                .help("New note (⌘N)")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    private var footer: some View {
        let text = store.current?.text ?? ""
        let words = text.split { $0.isWhitespace }.count
        return HStack {
            Text("\(store.notes.count) note\(store.notes.count == 1 ? "" : "s")")
            Spacer()
            Text("\(words) word\(words == 1 ? "" : "s") · \(text.count) chars")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

struct SwitcherView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: UIState
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = store.search(query)
        VStack(spacing: 0) {
            TextField("Search or create a note…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .focused($focused)
                .onSubmit { open(results) }
                .onKeyPress(.downArrow) { move(1, results.count); return .handled }
                .onKeyPress(.upArrow) { move(-1, results.count); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
                .onExitCommand { close() }
                .onChange(of: query) { selection = 0 }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, note in
                            row(note, selected: i == selection)
                                .id(i)
                                .contentShape(Rectangle())
                                .onTapGesture { selection = i; open(results) }
                        }
                        if results.isEmpty {
                            Text(query.isEmpty ? "No notes" : "↩  Create “\(query)”")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selection) { proxy.scrollTo(selection) }
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
        .padding(.horizontal, 20)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func row(_ note: Note, selected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !note.snippet.isEmpty {
                    Text(note.snippet).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if note.id == store.currentID {
                Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(note.modified, format: .relative(presentation: .named))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func move(_ d: Int, _ count: Int) {
        guard count > 0 else { return }
        selection = (selection + d + count) % count
    }

    private func open(_ results: [Note]) {
        if results.indices.contains(selection) {
            store.select(results[selection].id)
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            store.newNote(text: "# \(query)\n\n")
        }
        close()
    }

    private func close() {
        ui.showSwitcher = false
        ui.focusEditor()
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
