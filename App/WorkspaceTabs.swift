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
    let number: Int
    let terminal: TerminalViewState?

    var title: String { number == 1 ? kind.rawValue : "\(kind.rawValue) \(number)" }
}

@MainActor
@Observable
final class WorkspaceTabs {
    private(set) var items: [WorkspaceTab] = []
    private(set) var selection: UUID?
    private var numbers: [WorkspaceTabKind: Int] = [:]

    init(initialChanges: Bool = false) {
        if initialChanges { insert(.changes) }
    }

    func add(_ kind: WorkspaceTabKind, at directory: URL) {
        switch kind {
        case .changes:
            insert(kind)
        case .terminal:
            let terminal = TerminalViewState(controller: .shared)
            terminal.makePlatformView = { WorkspaceTerminalView(frame: .zero) }
            terminal.configuration = TerminalSurfaceOptions(workingDirectory: directory.path, context: .split)
            let tab = insert(kind, terminal: terminal)
            let id = tab.id
            terminal.onClose = { [weak self] _ in self?.close(id) }
            terminal.requestFocus()
        }
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

    @discardableResult
    private func insert(_ kind: WorkspaceTabKind, terminal: TerminalViewState? = nil) -> WorkspaceTab {
        let number = (numbers[kind] ?? 0) + 1
        numbers[kind] = number
        let tab = WorkspaceTab(kind: kind, number: number, terminal: terminal)
        items.append(tab)
        selection = tab.id
        return tab
    }
}
