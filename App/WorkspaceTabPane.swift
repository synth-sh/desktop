import SwiftUI

struct WorkspaceTabPane: View {
    @Environment(\.synthPalette) private var palette
    let directory: URL
    let turnCompletion: UInt64?
    let isVisible: Bool
    let tabs: WorkspaceTabs
    let addTerminalContext: (String) -> Void
    var browser: BrowserTab?
    var openBrowser: (() -> Void)?
    var closeBrowser: (() -> Void)?
    var toggleBottom: (() -> Void)?
    var showsBottom = false
    @State private var showsTabPicker = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.background)
        .foregroundStyle(palette.foreground)
        .onChange(of: isVisible) {
            if !isVisible { showsTabPicker = false }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(tabs.items) { tab in workspaceTabButton(tab).id(tab.id) }
                        if let browser {
                            tabButton(
                                "Browser", icon: "globe", selected: browser.isSelected,
                                select: { browser.isSelected = true }, close: { closeBrowser?() }
                            )
                            .id(browser.id)
                        }
                    }
                    .padding(.leading, 8)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedTabID) {
                    if let selectedTabID { scroll.scrollTo(selectedTabID) }
                }
            }

            addTabButton

            if let toggleBottom {
                let label = showsBottom ? "Hide Bottom Pane" : "Show Bottom Pane"
                Button(label, systemImage: "rectangle.split.1x2", action: toggleBottom)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(showsBottom ? palette.accent : palette.foreground)
                    .help(label)
            }
        }
        .padding(.trailing, 10)
        .frame(height: 35)
        .background(palette.surface)
    }

    private var selectedTabID: UUID? {
        browser?.isSelected == true ? browser?.id : tabs.selection
    }

    private var addTabButton: some View {
        ConversationDropdown(isPresented: $showsTabPicker, width: 170, arrowEdge: .bottom) {
            Label("Add Tab", systemImage: "plus")
                .labelStyle(.iconOnly)
        } content: {
            ConversationPopoverChoices(count: WorkspaceTabKind.allCases.count + (openBrowser == nil ? 0 : 1)) {
                ForEach(WorkspaceTabKind.allCases, id: \.self) { kind in
                    Button(kind.rawValue, systemImage: kind.icon) {
                        showsTabPicker = false
                        browser?.isSelected = false
                        switch kind {
                        case .changes: tabs.addChanges()
                        case .terminal: tabs.addTerminal(at: directory, addContext: addTerminalContext)
                        }
                    }
                }
                if let openBrowser {
                    Button("Browser", systemImage: "globe") {
                        showsTabPicker = false
                        openBrowser()
                    }
                }
            }
        }
        .buttonStyle(.borderless)
        .help("Add Tab")
    }

    private func workspaceTabButton(_ tab: WorkspaceTab) -> some View {
        tabButton(tabs.title(for: tab), icon: tab.kind.icon, selected: tab.id == selectedTabID) {
            browser?.isSelected = false
            tabs.select(tab)
        } close: {
            tabs.close(tab.id)
        }
    }

    private func tabButton(
        _ title: String, icon: String, selected: Bool, select: @escaping () -> Void, close: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Button(action: select) {
                Label(title, systemImage: icon)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button("Close \(title)", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.muted)
                .frame(width: 21, height: 26)
                .contentShape(Rectangle())
                .help("Close \(title)")
        }
        .buttonStyle(.plain)
        .font(.callout.weight(selected ? .semibold : .regular))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(selected ? palette.foreground : palette.muted)
        .background(selected ? palette.border : .clear, in: .rect(cornerRadius: 5))
    }

    private var content: some View {
        ZStack {
            if tabs.items.isEmpty && browser?.isSelected != true {
                ContentUnavailableView("No Tabs", systemImage: "rectangle.on.rectangle")
            }
            ForEach(tabs.items) { tab in
                let selected = tab.id == selectedTabID
                let visible = isVisible && selected
                tabContent(tab, visible: visible)
                    .opacity(selected ? 1 : 0)
                    .allowsHitTesting(visible)
                    .disabled(!visible)
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(!visible)
            }
            if let browser {
                let visible = isVisible && browser.isSelected
                BrowserWorkspaceView(tab: browser)
                    .id(browser.id)
                    .opacity(browser.isSelected ? 1 : 0)
                    .allowsHitTesting(visible)
                    .disabled(!visible)
                    .accessibilityHidden(!visible)
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: WorkspaceTab, visible: Bool) -> some View {
        if let terminal = tab.terminal {
            WorkspaceTerminalSurface(terminal: terminal, isVisible: visible)
        } else {
            GitReviewPane(directory: directory, turnCompletion: turnCompletion, isVisible: visible)
        }
    }
}
