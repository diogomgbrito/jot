import Foundation

struct Note: Identifiable, Equatable {
    let url: URL
    var text: String
    var modified: Date

    var id: URL { url }

    var title: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let t = Self.stripMarkup(first)
        return t.isEmpty ? "Untitled" : t
    }

    var snippet: String {
        let lines = text.split(whereSeparator: \.isNewline).dropFirst()
        let line = lines.lazy.map { Self.stripMarkup(String($0)) }.first { !$0.isEmpty } ?? ""
        return String(line.prefix(90))
    }

    private static func stripMarkup(_ line: String) -> String {
        line.replacingOccurrences(of: #"^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|>\s?)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Notes are plain Markdown files in one folder. Filenames are stable (creation timestamp);
/// the title is derived from the first line.
@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var currentID: URL?
    private(set) var folder: URL

    private var dirty: Set<URL> = []
    private var saveTask: Task<Void, Never>?
    private let fm = FileManager.default
    private let defaults = UserDefaults.standard

    var current: Note? { notes.first { $0.id == currentID } }
    var sorted: [Note] { notes.sorted { $0.modified > $1.modified } }

    init() {
        if let path = defaults.string(forKey: "notesFolder") {
            folder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Notes", isDirectory: true)
        }
        reload()
    }

    func setFolder(_ url: URL) {
        flush()
        folder = url
        defaults.set(url.path, forKey: "notesFolder")
        defaults.removeObject(forKey: "lastNote")
        currentID = nil
        reload()
    }

    /// Re-reads the folder from disk, keeping the current selection when possible.
    func reload() {
        flush()
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        notes = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return Note(url: url.standardizedFileURL, text: text, modified: date)
            }
            .sorted { $0.modified > $1.modified }

        if currentID == nil, let last = defaults.string(forKey: "lastNote") {
            currentID = folder.appendingPathComponent(last).standardizedFileURL
        }
        if current == nil { currentID = notes.first?.id }
        if current == nil { newNote() }
    }

    func updateCurrent(_ text: String) {
        guard let i = notes.firstIndex(where: { $0.id == currentID }), notes[i].text != text else { return }
        notes[i].text = text
        notes[i].modified = Date()
        dirty.insert(notes[i].id)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        for id in dirty {
            guard let note = notes.first(where: { $0.id == id }) else { continue }
            do { try note.text.write(to: note.url, atomically: true, encoding: .utf8) }
            catch { NSLog("Jot: failed to save \(note.url.path): \(error)") }
        }
        dirty.removeAll()
    }

    func select(_ id: URL) {
        guard id != currentID else { return }
        flush()
        discardIfEmpty(currentID)
        currentID = id
        defaults.set(id.lastPathComponent, forKey: "lastNote")
    }

    func newNote(text: String = "") {
        if let c = current, c.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !text.isEmpty { updateCurrent(text) }
            return
        }
        flush()
        let url = uniqueURL()
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, text: text, modified: Date())
        notes.insert(note, at: 0)
        select(note.id)
    }

    func deleteCurrent() {
        guard let c = current else { return }
        flush()
        let idx = sorted.firstIndex { $0.id == c.id } ?? 0
        try? fm.trashItem(at: c.url, resultingItemURL: nil)
        notes.removeAll { $0.id == c.id }
        currentID = nil
        let remaining = sorted
        if remaining.isEmpty { newNote() } else { select(remaining[min(idx, remaining.count - 1)].id) }
    }

    func cycle(_ offset: Int) {
        let order = sorted
        guard !order.isEmpty, let idx = order.firstIndex(where: { $0.id == currentID }) else { return }
        select(order[(idx + offset + order.count) % order.count].id)
    }

    func search(_ query: String) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.enumerated()
            .compactMap { i, n -> (Note, Int, Int)? in
                let t = n.title.lowercased()
                let score: Int
                if t.hasPrefix(q) { score = 4 }
                else if t.contains(q) { score = 3 }
                else if n.text.lowercased().contains(q) { score = 2 }
                else if Self.isSubsequence(q, of: t) { score = 1 }
                else { return nil }
                return (n, score, i)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }

    private func discardIfEmpty(_ id: URL?) {
        guard let id, let n = notes.first(where: { $0.id == id }),
              n.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? fm.removeItem(at: n.url)
        notes.removeAll { $0.id == id }
    }

    private func uniqueURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let base = f.string(from: Date())
        var url = folder.appendingPathComponent("\(base).md")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(n).md")
            n += 1
        }
        return url.standardizedFileURL
    }

    private static func isSubsequence(_ needle: String, of hay: String) -> Bool {
        var it = hay.makeIterator()
        return needle.allSatisfy { c in
            while let h = it.next() { if h == c { return true } }
            return false
        }
    }
}
