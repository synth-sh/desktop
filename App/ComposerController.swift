import AppKit
import MarkdownEngine
import Observation
import SynthClient

@MainActor
@Observable
final class ComposerController {
    enum Action: String {
        case new, model, mode, compact, stop

        var title: String {
            switch self {
            case .new: "New conversation"
            case .model: "Choose model"
            case .mode: "Choose mode"
            case .compact: "Compact conversation"
            case .stop: "Stop turn"
            }
        }
    }

    struct Choice: Identifiable {
        let id: String
        let title: String
        let detail: String
        var insertion: String?
        var action: Action?
    }

    private struct Query: Equatable {
        let prefix: String
        let range: NSRange

        var isFile: Bool { prefix.hasPrefix("@") }
        var filter: String { String(prefix.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }

        @MainActor init?(view: NSTextView, inCode: Bool) {
            let caret = view.selectedRange()
            let text = view.string as NSString
            guard !inCode, !view.hasMarkedText(), caret.length == 0, caret.location <= text.length else { return nil }
            let before = text.substring(to: caret.location)
            if before.hasPrefix("/"), !before.contains(where: \.isWhitespace) {
                prefix = before
                range = NSRange(location: 0, length: caret.location)
                return
            }
            guard let trigger = before.lastIndex(of: "@"), Self.isBoundary(trigger, in: before) else { return nil }
            let suffix = before[before.index(after: trigger)...]
            guard Self.acceptsPathPrefix(suffix) else { return nil }
            prefix = "@" + suffix
            range = NSRange(trigger..<before.endIndex, in: before)
        }

        private static func isBoundary(_ index: String.Index, in text: String) -> Bool {
            guard index != text.startIndex else { return true }
            let previous = text[text.index(before: index)]
            return previous.isWhitespace || "([{".contains(previous)
        }

        private static func acceptsPathPrefix(_ suffix: Substring) -> Bool {
            guard !suffix.contains(where: \.isNewline) else { return false }
            return suffix.hasPrefix("\"") || !suffix.contains(where: \.isWhitespace)
        }
    }

    private(set) weak var textView: NSTextView?
    private(set) var choices: [Choice] = []
    private(set) var selection = 0
    private(set) var height: CGFloat = 40
    private var pathLookupError: String?
    private var session: String?
    private var query: Query?
    private var dismissedQuery: Query?
    private var paths: [String]?
    private var inCode = false
    private var observedSelection: NSRange?
    private var suppressedSelection = false
    private let busID = UUID().uuidString

    private var isCompletingFiles: Bool { query?.isFile == true && query != dismissedQuery }
    var fileError: String? { isCompletingFiles ? pathLookupError : nil }
    var showsCompletions: Bool { !choices.isEmpty || isCompletingFiles }
    var fileRequest: String? {
        isCompletingFiles && paths == nil && pathLookupError == nil ? session : nil
    }

    func refreshFiles() {
        paths = nil
        pathLookupError = nil
        if isCompletingFiles { choices = [] }
    }

    private func reset() {
        session = nil
        query = nil
        dismissedQuery = nil
        choices = []
        refreshFiles()
        textView = nil
        observedSelection = nil
        height = 40
    }

    func update(_ view: NSTextView, inCode: Bool, model: ConversationModel, session: String) {
        guard model.sessionID == session, !suppressedSelection else { return }
        if self.session != session { reset(); self.session = session }
        self.inCode = inCode
        textView = view
        let range = view.selectedRange()
        if observedSelection != range {
            observedSelection = range
            revealCaret(in: session)
        }
        if let measured = view.textLayoutManager?.usageBoundsForTextContainer.height, measured.isFinite {
            height = max(40, ceil(measured) + 8)
        }
        let next = Query(view: view, inCode: inCode)
        if next != dismissedQuery { dismissedQuery = nil }
        if query != next { selection = 0 }
        query = next
        refreshChoices(model)
    }

    func receiveFiles(_ paths: [String], model: ConversationModel, session: String) {
        guard self.session == session, model.sessionID == session, !Task.isCancelled else { return }
        self.paths = paths
        refreshChoices(model)
    }

    func failFiles(_ error: any Error, session: String) {
        if self.session == session && !Task.isCancelled { pathLookupError = error.localizedDescription }
    }

    private func refreshChoices(_ model: ConversationModel) {
        guard let query, query != dismissedQuery else { choices = []; return }
        choices = query.isFile ? fileChoices(query.filter) : slashChoices(query.filter, model: model)
        selection = min(selection, max(0, choices.count - 1))
    }

    private func fileChoices(_ filter: String) -> [Choice] {
        let candidates = (paths ?? []).lazy.filter(FileReference.canMention)
        let needle = filter.lowercased()
        var ranked = Array(candidates.filter { $0.lowercased().hasPrefix(needle) }.prefix(40))
        if ranked.count < 40 {
            ranked += candidates.filter {
                !$0.lowercased().hasPrefix(needle) && $0.localizedCaseInsensitiveContains(filter)
            }.prefix(40 - ranked.count)
        }
        return ranked.map { path in
            Choice(id: path, title: "@" + path, detail: "Attach project contents",
                   insertion: FileReference.markdown(path: path) + " ")
        }
    }

    private func slashChoices(_ filter: String, model: ConversationModel) -> [Choice] {
        var actions: [Action] = []
        if model.canSwitch { actions.append(.new) }
        if model.canConfigure { actions += [.model, .mode, .compact] }
        if model.canStop { actions.append(.stop) }
        var offered = actions.map { Choice(id: $0.rawValue, title: "/" + $0.rawValue, detail: $0.title, action: $0) }
        if model.canConfigure {
            offered += (model.state?.skills ?? []).map { skill in
                let name = skill.description.isEmpty ? skill.name : skill.description
                return Choice(id: "skill:" + skill.id, title: "/" + skill.id, detail: name + " · " + skill.dir,
                              insertion: "/" + skill.id + " ")
            }
        }
        guard !filter.isEmpty else { return offered }
        return offered.filter { ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(filter) }
    }

    func key(_ event: NSEvent, model: ConversationModel, session: String) -> Bool {
        guard model.sessionID == session else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if modifiers == .command {
            let shortcuts = ["b": "bold", "i": "italic", "k": "link"]
            if let format = shortcuts[event.charactersIgnoringModifiers ?? ""] {
                apply(format)
                return true
            }
        }
        if modifiers.isEmpty, handleCompletion(event.keyCode, model: model, session: session) { return true }
        guard modifiers.isEmpty || modifiers == .command, [36, 76].contains(event.keyCode) else { return false }
        DispatchQueue.main.async {
            Task { await model.send(in: session) }
        }
        return true
    }

    private func handleCompletion(_ key: UInt16, model: ConversationModel, session: String) -> Bool {
        if key == 53, !choices.isEmpty || isCompletingFiles {
            dismissedQuery = query
            choices = []
            return true
        }
        if fileRequest != nil, [36, 76].contains(key) { return true }
        guard !choices.isEmpty else { return false }
        switch key {
        case 125: selection = (selection + 1) % choices.count
        case 126: selection = (selection + choices.count - 1) % choices.count
        case 36, 76, 48: choose(selection, model: model, session: session)
        default: return false
        }
        return true
    }

    func choose(_ index: Int, model: ConversationModel, session: String) {
        guard model.sessionID == session, choices.indices.contains(index),
              let textView, let query, query == Query(view: textView, inCode: inCode) else { return }
        let choice = choices[index]
        suppressedSelection = true
        textView.insertText(choice.insertion ?? "", replacementRange: query.range)
        suppressedSelection = false
        self.query = nil
        choices = []
        if let action = choice.action { perform(action, model: model) }
    }

    private func perform(_ action: Action, model: ConversationModel) {
        switch action {
        case .new:
            Task { await model.open(in: model.project) }
        case .model: model.showModelPicker = true
        case .mode: model.showModePicker = true
        case .stop: Task { await model.stop() }
        case .compact: Task { await model.compact() }
        }
    }

    func insert(_ text: String) -> Bool {
        guard let textView else { return false }
        textView.window?.makeFirstResponder(textView)
        textView.insertText(text, replacementRange: textView.selectedRange())
        return true
    }

    func apply(_ format: String) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        NotificationCenter.default.post(name: .init(busID + format), object: nil, userInfo: ["level": 2])
    }

    var bus: MarkdownEditorBus {
        .init(applyBoldRequest: .init(busID + "bold"), applyItalicRequest: .init(busID + "italic"),
              applyHeadingRequest: .init(busID + "heading"),
              applyInlineCodeRequest: .init(busID + "code"), applyBlockquoteRequest: .init(busID + "quote"),
              applyUnorderedListRequest: .init(busID + "list"), applyOrderedListRequest: .init(busID + "numbered"),
              applyLinkRequest: .init(busID + "link"), applyCodeBlockRequest: .init(busID + "block"))
    }
}

extension ComposerController {
    func revealCaret(in session: String) {
        guard self.session == session, let textView, textView.window?.firstResponder === textView,
              let scroller = textView.enclosingScrollView else { return }
        let range = NSRange(location: NSMaxRange(textView.selectedRange()), length: 0)
        let clip = scroller.contentView
        var target = clip.bounds
        if range.location == textView.textStorage?.length {
            target.origin.y = clip.documentRect.maxY - target.height
        } else if let rect = caretRect(for: range, in: textView) {
            let caret = textView.convert(rect, to: clip)
            let margin = textView.textContainerInset.height
            target.origin.y = min(max(target.minY, caret.maxY - target.height + margin), caret.minY - margin)
        } else {
            textView.scrollRangeToVisible(range)
            return
        }
        let origin = clip.constrainBoundsRect(target).origin
        guard origin != clip.bounds.origin else { return }
        clip.scroll(to: origin)
        scroller.reflectScrolledClipView(clip)
    }

    private func caretRect(for range: NSRange, in textView: NSTextView) -> CGRect? {
        guard let layout = textView.textLayoutManager, let content = layout.textContentManager,
              let location = content.location(layout.documentRange.location, offsetBy: range.location),
              let prefix = NSTextRange(location: layout.documentRange.location, end: location) else { return nil }
        layout.ensureLayout(for: prefix)
        var caret: CGRect?
        let caretRange = NSTextRange(location: location)
        layout.enumerateTextSegments(in: caretRange, type: .standard, options: []) { _, rect, _, _ in
            guard rect.height > 0 else { return true }
            let origin = textView.textContainerOrigin
            caret = rect.offsetBy(dx: origin.x, dy: origin.y)
            return false
        }
        return caret
    }
}
