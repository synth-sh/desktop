import SwiftUI

struct WorkspaceTabPane: View {
    @Environment(\.synthPalette) private var palette
    let directory: URL
    let turnCompletion: UInt64?
    let isVisible: Bool
    let tabs: WorkspaceTabs
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
                        ForEach(tabs.items) { tab in tabButton(tab).id(tab.id) }
                    }
                    .padding(.leading, 8)
                }
                .scrollIndicators(.hidden)
                .onChange(of: tabs.selection) {
                    if let selection = tabs.selection { scroll.scrollTo(selection) }
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

    private var addTabButton: some View {
        ConversationDropdown(isPresented: $showsTabPicker, width: 170, arrowEdge: .bottom) {
            Label("Add Tab", systemImage: "plus")
                .labelStyle(.iconOnly)
        } content: {
            ConversationPopoverChoices(count: WorkspaceTabKind.allCases.count) {
                ForEach(WorkspaceTabKind.allCases, id: \.self) { kind in
                    Button(kind.rawValue, systemImage: kind.icon) {
                        showsTabPicker = false
                        tabs.add(kind, at: directory)
                    }
                }
            }
        }
        .buttonStyle(.borderless)
        .help("Add Tab")
    }

    private func tabButton(_ tab: WorkspaceTab) -> some View {
        let selected = tabs.selection == tab.id
        return HStack(spacing: 2) {
            Button {
                tabs.select(tab)
            } label: {
                Label(tab.title, systemImage: tab.kind.icon)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button("Close \(tab.title)", systemImage: "xmark") { tabs.close(tab.id) }
                .labelStyle(.iconOnly)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.muted)
                .frame(width: 21, height: 26)
                .contentShape(Rectangle())
                .help("Close \(tab.title)")
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
            if tabs.items.isEmpty {
                ContentUnavailableView("No Tabs", systemImage: "rectangle.on.rectangle")
            }
            ForEach(tabs.items) { tab in
                let selected = tab.id == tabs.selection
                let visible = isVisible && selected
                tabContent(tab, visible: visible)
                    .opacity(selected ? 1 : 0)
                    .allowsHitTesting(visible)
                    .disabled(!visible)
                    .accessibilityElement(children: .contain)
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
