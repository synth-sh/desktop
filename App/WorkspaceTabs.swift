import Foundation
import GhosttyTerminal
import Observation

enum WorkspaceTabKind: String, CaseIterable {
    case changes = "Git Changes"
    case terminal = "Terminal"

    var icon: String {
        switch self {
        case .changes: "arrow.triangle.branch"
        case .terminal: "terminal"
        }
    }
}

struct WorkspaceTab: Identifiable {
    let id = UUID()
    let kind: WorkspaceTabKind
    let terminal: TerminalViewState?
}

@MainActor
@Observable
final class WorkspaceTabs {
    private(set) var items: [WorkspaceTab] = []
    private(set) var selection: UUID?
    init(initialChanges: Bool = false) {
        if initialChanges { addChanges() }
    }

    func title(for tab: WorkspaceTab) -> String {
        let preceding = items.prefix { $0.id != tab.id }.lazy.filter { $0.kind == tab.kind }.count
        return preceding == 0 ? tab.kind.rawValue : "\(tab.kind.rawValue) \(preceding + 1)"
    }

    func addChanges() {
        insert(WorkspaceTab(kind: .changes, terminal: nil))
    }

    func addTerminal(at directory: URL, addContext: @escaping (String) -> Void) {
        let terminal = TerminalViewState(controller: .shared)
        terminal.makePlatformView = {
            let view = WorkspaceTerminalView(frame: .zero)
            view.addContext = addContext
            return view
        }
        terminal.configuration = TerminalSurfaceOptions(workingDirectory: directory.path, context: .split)
        let tab = WorkspaceTab(kind: .terminal, terminal: terminal)
        insert(tab)
        let id = tab.id
        terminal.onClose = { [weak self] _ in self?.close(id) }
        terminal.requestFocus()
    }

    func select(_ tab: WorkspaceTab) {
        selection = tab.id
        tab.terminal?.requestFocus()
    }

    func close(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        if selection == id { selection = index < items.count ? items[index].id : items.last?.id }
    }

    private func insert(_ tab: WorkspaceTab) {
        items.append(tab)
        selection = tab.id
    }
}
