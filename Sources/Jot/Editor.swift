import AppKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let noteID: URL?
    let ui: UIState
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = MarkdownTextView(usingTextLayoutManager: false)
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 14, height: 8)
        tv.font = MarkdownHighlighter.baseFont
        tv.typingAttributes = MarkdownHighlighter.baseAttributes
        tv.insertionPointColor = .controlAccentColor
        tv.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = context.coordinator
        tv.textStorage?.delegate = context.coordinator.highlighter

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = tv

        ui.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = scroll.documentView as? MarkdownTextView else { return }
        tv.onEscape = onEscape

        if !c.loaded || c.noteID != noteID {
            // Switched notes: load fresh content, reset undo, cursor to end.
            c.loaded = true
            c.noteID = noteID
            tv.string = text
            tv.undoManager?.removeAllActions()
            let end = (text as NSString).length
            tv.setSelectedRange(NSRange(location: end, length: 0))
            tv.scrollRangeToVisible(NSRange(location: end, length: 0))
        } else if tv.string != text {
            // Changed on disk while open.
            let sel = tv.selectedRange()
            tv.string = text
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var noteID: URL?
        var loaded = false
        let highlighter = MarkdownHighlighter()

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - Text view

final class MarkdownTextView: NSTextView {
    var onEscape: (() -> Void)?

    static let taskRegex = try! NSRegularExpression(pattern: #"^[ \t]*[-*+][ \t]+(\[([ xX])\])"#, options: .anchorsMatchLines)
    static let listPrefixRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+][ \t]+\[[ xX]\][ \t]+|[-*+][ \t]+|(\d+)([.)])[ \t]+|>[ \t]?)"#)

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    /// Replaces text through the undo-aware path.
    func replace(_ range: NSRange, with s: String) {
        guard shouldChangeText(in: range, replacementString: s) else { return }
        textStorage?.replaceCharacters(in: range, with: s)
        didChangeText()
    }

    // Continue lists / quotes on Return; an empty item ends the list.
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let head = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
        guard sel.length == 0,
              let m = Self.listPrefixRegex.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length))
        else { return super.insertNewline(sender) }

        let headNS = head as NSString
        let lineText = ns.substring(with: line).trimmingCharacters(in: .newlines) as NSString
        let rest = lineText.substring(from: min(m.range.length, lineText.length)).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty {
            replace(NSRange(location: line.location, length: m.range.length), with: "")
            setSelectedRange(NSRange(location: line.location, length: 0))
            return
        }

        var prefix = headNS.substring(with: m.range)
        if m.range(at: 3).location != NSNotFound, let n = Int(headNS.substring(with: m.range(at: 3))) {
            prefix = headNS.substring(with: m.range(at: 1)) + "\(n + 1)" + headNS.substring(with: m.range(at: 4)) + " "
        }
        prefix = prefix.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
        super.insertNewline(sender)
        insertText(prefix, replacementRange: selectedRange())
    }

    // Tab / Shift-Tab indent list items.
    override func insertTab(_ sender: Any?) {
        guard let line = currentListLine() else { return super.insertTab(sender) }
        let sel = selectedRange()
        replace(NSRange(location: line.location, length: 0), with: "  ")
        setSelectedRange(NSRange(location: sel.location + 2, length: sel.length))
    }

    override func insertBacktab(_ sender: Any?) {
        guard let line = currentListLine() else { return super.insertBacktab(sender) }
        let ns = string as NSString
        let sel = selectedRange()
        var n = 0
        while n < 2, line.location + n < ns.length, ns.character(at: line.location + n) == 0x20 { n += 1 }
        if n == 0, line.location < ns.length, ns.character(at: line.location) == 0x09 { n = 1 }
        guard n > 0 else { return }
        replace(NSRange(location: line.location, length: n), with: "")
        setSelectedRange(NSRange(location: max(line.location, sel.location - n), length: sel.length))
    }

    private func currentListLine() -> NSRange? {
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let text = ns.substring(with: line)
        let isList = Self.listPrefixRegex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
            && !text.trimmingCharacters(in: .whitespaces).hasPrefix(">")
        return isList ? line : nil
    }

    // Click on "[ ]" / "[x]" toggles the checkbox.
    override func mouseDown(with event: NSEvent) {
        if let lm = layoutManager, let tc = textContainer {
            var p = convert(event.locationInWindow, from: nil)
            p.x -= textContainerOrigin.x
            p.y -= textContainerOrigin.y
            var fraction: CGFloat = 0
            let glyph = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &fraction)
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
            if rect.contains(p), toggleCheckbox(at: lm.characterIndexForGlyph(at: glyph)) { return }
        }
        super.mouseDown(with: event)
    }

    private func toggleCheckbox(at index: Int) -> Bool {
        let ns = string as NSString
        guard index < ns.length else { return false }
        let line = ns.lineRange(for: NSRange(location: index, length: 0))
        guard let m = Self.taskRegex.firstMatch(in: string, range: line), NSLocationInRange(index, m.range(at: 1)) else { return false }
        let mark = m.range(at: 2)
        replace(mark, with: ns.substring(with: mark) == " " ? "x" : " ")
        return true
    }

    // MARK: Formatting commands (wired from the Edit menu)

    @objc func jotBold(_ sender: Any?) { wrap("**") }
    @objc func jotItalic(_ sender: Any?) { wrap("_") }
    @objc func jotStrikethrough(_ sender: Any?) { wrap("~~") }
    @objc func jotCode(_ sender: Any?) { wrap("`") }

    @objc func jotChecklist(_ sender: Any?) { toggleList(.task) }
    @objc func jotBulletList(_ sender: Any?) { toggleList(.bullet) }
    @objc func jotNumberedList(_ sender: Any?) { toggleList(.numbered) }
    @objc func jotQuote(_ sender: Any?) { toggleList(.quote) }
    @objc func jotHeading1(_ sender: Any?) { setHeading(1) }
    @objc func jotHeading2(_ sender: Any?) { setHeading(2) }
    @objc func jotHeading3(_ sender: Any?) { setHeading(3) }
    @objc func jotBodyText(_ sender: Any?) { setHeading(0) }

    @objc func jotHeading(_ sender: Any?) {
        let ns = string as NSString
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: selectedRange().location, length: 0)))
        let hashes = line.prefix { $0 == "#" }.count
        setHeading(hashes >= 3 ? 0 : hashes + 1) // none → # → ## → ### → none
    }

    @objc func jotLink(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        let selected = ns.substring(with: sel)
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            replace(sel, with: "[](\(selected))")
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        } else {
            replace(sel, with: "[\(selected)]()")
            let caret = sel.location + (selected as NSString).length + (selected.isEmpty ? 1 : 3)
            setSelectedRange(NSRange(location: caret, length: 0))
        }
    }

    @objc func jotCodeBlock(_ sender: Any?) {
        let ns = string as NSString
        let lines = ns.lineRange(for: selectedRange())
        var body = ns.substring(with: lines)
        let hadNewline = body.hasSuffix("\n")
        if hadNewline { body.removeLast() }
        let replacement = "```\n" + body + "\n```" + (hadNewline ? "\n" : "")
        replace(lines, with: replacement)
        setSelectedRange(NSRange(location: lines.location + 4 + (body as NSString).length, length: 0))
    }

    enum ListKind { case bullet, numbered, task, quote }

    private static let linePrefixRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+][ \t]+\[[ xX]\][ \t]+|[-*+][ \t]+|\d+[.)][ \t]+|>[ \t]?)?"#)

    /// Applies a list / quote style to every selected line, or removes it if all lines already have it.
    func toggleList(_ kind: ListKind) {
        let parsed = selectedLines().map { line -> (indent: String, marker: String, rest: String) in
            let ns = line as NSString
            let m = Self.linePrefixRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))!
            let marker = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            return (ns.substring(with: m.range(at: 1)), marker, ns.substring(from: m.range.length))
        }
        func kindOf(_ marker: String) -> ListKind? {
            if marker.isEmpty { return nil }
            if marker.hasPrefix(">") { return .quote }
            if marker.contains("[") { return .task }
            if marker.first?.isNumber == true { return .numbered }
            return .bullet
        }
        let removing = parsed.allSatisfy { kindOf($0.marker) == kind }
        var n = 0
        let lines = parsed.map { p -> String in
            if removing { return p.indent + p.rest }
            if p.rest.isEmpty && parsed.count > 1 { return p.indent }
            n += 1
            let marker: String
            switch kind {
            case .bullet: marker = "- "
            case .numbered: marker = "\(n). "
            case .task: marker = "- [ ] "
            case .quote: marker = "> "
            }
            return p.indent + marker + p.rest
        }
        replaceSelectedLines(with: lines)
    }

    func setHeading(_ level: Int) {
        let lines = selectedLines().map { line -> String in
            let stripped = line.replacingOccurrences(of: #"^#{1,6}[ \t]+"#, with: "", options: .regularExpression)
            return level == 0 ? stripped : String(repeating: "#", count: level) + " " + stripped
        }
        replaceSelectedLines(with: lines)
    }

    private func selectedLines() -> [String] {
        let ns = string as NSString
        var text = ns.substring(with: ns.lineRange(for: selectedRange()))
        if text.hasSuffix("\n") { text.removeLast() }
        return text.components(separatedBy: "\n")
    }

    private func replaceSelectedLines(with lines: [String]) {
        let ns = string as NSString
        let sel = selectedRange()
        var range = ns.lineRange(for: sel)
        if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == 0x0A { range.length -= 1 }
        let joined = lines.joined(separator: "\n")
        replace(range, with: joined)
        let length = (joined as NSString).length
        if sel.length == 0 && lines.count == 1 {
            setSelectedRange(NSRange(location: range.location + length, length: 0))
        } else {
            setSelectedRange(NSRange(location: range.location, length: length))
        }
    }

    private func wrap(_ marker: String) {
        let ns = string as NSString
        let sel = selectedRange()
        let inner = ns.substring(with: sel)
        let m = (marker as NSString).length
        if sel.location >= m, NSMaxRange(sel) + m <= ns.length,
           ns.substring(with: NSRange(location: sel.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: m)) == marker {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            replace(outer, with: inner)
            setSelectedRange(NSRange(location: outer.location, length: sel.length))
            return
        }
        replace(sel, with: marker + inner + marker)
        setSelectedRange(NSRange(location: sel.location + m, length: sel.length))
    }
}

// MARK: - Highlighter

/// Styles Markdown in place; syntax stays visible but dimmed.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    static let fontSize: CGFloat = 14
    static let baseFont = NSFont.systemFont(ofSize: fontSize)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
    static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        return p
    }()
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    private static func re(_ p: String, _ o: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: o)
    }

    private static let heading = re(#"^(#{1,6})[ \t]+(.*)$"#)
    private static let task = re(#"^[ \t]*([-*+])[ \t]+(\[([ xX])\])[ \t]+(.*)$"#)
    private static let list = re(#"^[ \t]*([-*+]|\d+[.)])[ \t]+"#)
    private static let quote = re(#"^(>+)[ \t]?(.*)$"#)
    private static let rule = re(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
    private static let bold = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = re(#"(?<![*_\w])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*_\w])"#)
    private static let strike = re(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let link = re(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private static let url = re(#"(?<![(<\w])https?://[^\s)>\]]+"#)
    private static let inlineCode = re(#"`[^`\n]+`"#)
    private static let fence = re(#"^```[\s\S]*?(?:^```[ \t]*$|\z)"#, [.anchorsMatchLines])

    private let dim = NSColor.tertiaryLabelColor
    private let codeBackground = NSColor.secondaryLabelColor.withAlphaComponent(0.1)

    func textStorage(_ ts: NSTextStorage, willProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength: Int) {
        guard mask.contains(.editedCharacters) else { return }
        highlight(ts)
    }

    func highlight(_ ts: NSTextStorage) {
        let s = ts.string
        let full = NSRange(location: 0, length: (s as NSString).length)
        ts.setAttributes(Self.baseAttributes, range: full)

        func each(_ r: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            r.enumerateMatches(in: s, range: full) { m, _, _ in if let m { body(m) } }
        }

        each(Self.heading) { m in
            let level = m.range(at: 1).length
            let size: CGFloat = [22, 19, 17, 15, 14, 14][level - 1]
            ts.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: m.range)
            ts.addAttribute(.foregroundColor, value: dim, range: m.range(at: 1))
        }
        each(Self.list) { m in
            ts.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range(at: 1))
        }
        each(Self.task) { m in
            ts.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range(at: 2))
            ts.addAttribute(.font, value: Self.monoFont, range: m.range(at: 2))
            ts.addAttribute(.cursor, value: NSCursor.pointingHand, range: m.range(at: 2))
            if (s as NSString).substring(with: m.range(at: 3)) != " " {
                ts.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 4))
                ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 4))
            }
        }
        each(Self.quote) { m in
            ts.addAttribute(.foregroundColor, value: dim, range: m.range(at: 1))
            ts.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 2))
            addTrait(ts, .italicFontMask, m.range(at: 2))
        }
        each(Self.rule) { m in ts.addAttribute(.foregroundColor, value: dim, range: m.range) }
        each(Self.bold) { m in
            addTrait(ts, .boldFontMask, m.range)
            dimMarkers(ts, m.range, m.range(at: 1).length)
        }
        each(Self.italic) { m in
            addTrait(ts, .italicFontMask, m.range)
            dimMarkers(ts, m.range, 1)
        }
        each(Self.strike) { m in
            ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            dimMarkers(ts, m.range, 2)
        }
        each(Self.link) { m in
            ts.addAttribute(.foregroundColor, value: dim, range: m.range)
            ts.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range(at: 1))
            if let url = URL(string: (s as NSString).substring(with: m.range(at: 2))) {
                ts.addAttribute(.link, value: url, range: m.range(at: 1))
            }
        }
        each(Self.url) { m in
            if let url = URL(string: (s as NSString).substring(with: m.range)) {
                ts.addAttribute(.link, value: url, range: m.range)
            }
        }
        for r in [Self.inlineCode, Self.fence] {
            each(r) { m in
                ts.removeAttribute(.link, range: m.range)
                ts.removeAttribute(.strikethroughStyle, range: m.range)
                ts.addAttribute(.font, value: Self.monoFont, range: m.range)
                ts.addAttribute(.foregroundColor, value: NSColor.labelColor, range: m.range)
                ts.addAttribute(.backgroundColor, value: codeBackground, range: m.range)
            }
        }
    }

    private func dimMarkers(_ ts: NSTextStorage, _ r: NSRange, _ len: Int) {
        ts.addAttribute(.foregroundColor, value: dim, range: NSRange(location: r.location, length: len))
        ts.addAttribute(.foregroundColor, value: dim, range: NSRange(location: NSMaxRange(r) - len, length: len))
    }

    private func addTrait(_ ts: NSTextStorage, _ trait: NSFontTraitMask, _ r: NSRange) {
        ts.enumerateAttribute(.font, in: r) { value, sub, _ in
            let font = (value as? NSFont) ?? Self.baseFont
            ts.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
        }
    }
}
