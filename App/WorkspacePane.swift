import SwiftUI

struct WorkspacePane: View {
    @Environment(\.synthPalette) private var palette
    let directory: URL?
    let openDirectories: Set<URL>
    let turnCompletion: UInt64?
    let addTerminalContext: (String) -> Void
    let hideWorkspace: () -> Void
    @State private var openedDirectories: [URL] = []

    var body: some View {
        ZStack {
            palette.background
            ForEach(openedDirectories, id: \.self) { root in
                let visible = root == directory
                WorkspaceSplit(
                    directory: root, turnCompletion: visible ? turnCompletion : nil, isVisible: visible,
                    addTerminalContext: addTerminalContext, hideWorkspace: hideWorkspace
                )
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .disabled(!visible)
                .accessibilityElement(children: .contain)
                .accessibilityHidden(!visible)
            }
        }
        .onChange(of: directory, initial: true) {
            if let directory, !openedDirectories.contains(directory) { openedDirectories.append(directory) }
        }
        .onChange(of: openDirectories) {
            openedDirectories.removeAll { !openDirectories.contains($0) }
        }
    }
}

private struct WorkspaceSplit: View {
    let directory: URL
    let turnCompletion: UInt64?
    let isVisible: Bool
    let addTerminalContext: (String) -> Void
    let hideWorkspace: () -> Void
    @AppStorage("workspaceBottomPaneHeight") private var bottomHeight = 0.0
    @State private var showsBottom = false
    @State private var topTabs = WorkspaceTabs(initialChanges: true)
    @State private var bottomTabs = WorkspaceTabs()

    var body: some View {
        ResizableEdgePane(
            savedSize: $bottomHeight, axis: .vertical, isPresented: showsBottom,
            defaultSize: 260, minimumSize: 145, minimumMainSize: 170,
            dividerLabel: "Bottom pane height", keepsPaneMounted: true
        ) {
            WorkspaceTabPane(
                directory: directory, turnCompletion: turnCompletion, isVisible: isVisible, tabs: topTabs,
                addTerminalContext: addTerminalContext, toggleBottom: toggleBottom, showsBottom: showsBottom
            )
        } pane: {
            WorkspaceTabPane(
                directory: directory, turnCompletion: turnCompletion, isVisible: isVisible && showsBottom,
                tabs: bottomTabs, addTerminalContext: addTerminalContext
            )
        }
        .onChange(of: bottomTabs.items.isEmpty) { _, empty in
            if empty { showsBottom = false }
        }
        .onChange(of: hasNoTabs) { _, empty in
            if empty && isVisible { hideWorkspace() }
        }
        .onChange(of: isVisible) {
            if isVisible && hasNoTabs { topTabs.addChanges() }
        }
    }

    private var hasNoTabs: Bool { topTabs.items.isEmpty && bottomTabs.items.isEmpty }

    private func toggleBottom() {
        showsBottom.toggle()
        if showsBottom && bottomTabs.items.isEmpty {
            bottomTabs.addTerminal(at: directory, addContext: addTerminalContext)
        }
    }
}
