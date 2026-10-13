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
    @ObservedObject var shortcuts: ShortcutStore
    @AppStorage("formatBarOpen") private var formatBarOpen = false
    let onEscape: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                MarkdownEditor(
                    text: Binding(get: { store.current?.text ?? "" }, set: { store.updateCurrent($0) }),
                    noteID: store.currentID,
                    ui: ui,
                    onEscape: onEscape)
                Text("\(store.current?.text.count ?? 0) characters")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .opacity(formatBarOpen ? 0 : 1)  // the open bar covers it
            }
            FormatBar(ui: ui, shortcuts: shortcuts)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
        }
        .overlay(alignment: .top) {
            if ui.showSwitcher {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.08)
                        .contentShape(Rectangle())
                        .onTapGesture { ui.showSwitcher = false; ui.focusEditor() }
                    SwitcherView(store: store, ui: ui)
                        .padding(.top, 4)
                }
            }
        }
        .background(VisualEffectBackground().ignoresSafeArea())
    }
}

/// Centred note title shown in the window toolbar.
struct TitleView: View {
    @ObservedObject var store: NoteStore

    var body: some View {
        Text(store.current?.title ?? "Jot")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: 260)
            .fixedSize()
    }
}

/// Collapsible formatting bar in the bottom-right corner, like Raycast Notes.
struct FormatBar: View {
    @ObservedObject var ui: UIState
    @ObservedObject var shortcuts: ShortcutStore
    @AppStorage("formatBarOpen") private var open = false

    private func apply(_ action: (MarkdownTextView) -> Void) {
        guard let tv = ui.textView as? MarkdownTextView else { return }
        tv.window?.makeFirstResponder(tv)
        action(tv)
    }

    var body: some View {
        HStack(spacing: 8) {
            if open {
                HStack(spacing: 4) {
                    Menu {
                        Button("Heading 1") { apply { $0.setHeading(1) } }
                        Button("Heading 2") { apply { $0.setHeading(2) } }
                        Button("Heading 3") { apply { $0.setHeading(3) } }
                        Button("Body Text") { apply { $0.setHeading(0) } }
                    } label: {
                        Text("H").font(.system(size: 16, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Heading")

                    Menu {
                        Button("Bold") { apply { $0.jotBold(nil) } }
                        Button("Italic") { apply { $0.jotItalic(nil) } }
                        Button("Strikethrough") { apply { $0.jotStrikethrough(nil) } }
                    } label: {
                        Image(systemName: "textformat")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Text style")

                    tool("link", .link) { $0.jotLink(nil) }
                    tool("chevron.left.forwardslash.chevron.right", .inlineCode) { $0.jotCode(nil) }
                    Divider().frame(height: 18).padding(.horizontal, 4)
                    tool("curlybraces.square", .codeBlock) { $0.jotCodeBlock(nil) }
                    tool("text.quote", .quote) { $0.jotQuote(nil) }
                    Divider().frame(height: 18).padding(.horizontal, 4)

                    Menu {
                        Button("Bulleted List") { apply { $0.toggleList(.bullet) } }
                        Button("Numbered List") { apply { $0.toggleList(.numbered) } }
                        Button("Checklist") { apply { $0.toggleList(.task) } }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Lists")
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                withAnimation(.snappy(duration: 0.2)) { open.toggle() }
            } label: {
                Group {
                    if open { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                    else { Text("T").font(.system(size: 17, weight: .medium, design: .serif)) }
                }
                .frame(width: 36, height: 36)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(.primary.opacity(0.1)))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(open ? "Hide formatting" : "Formatting")
        }
        .foregroundStyle(.secondary)
    }

    private func tool(_ symbol: String, _ id: ShortcutID, _ action: @escaping (MarkdownTextView) -> Void) -> some View {
        Button { apply(action) } label: {
            Image(systemName: symbol).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(id.title + shortcuts.hint(id))
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
