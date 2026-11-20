import SwiftUI
import SynthClient

struct GitReviewHeader: View {
    @Environment(\.synthPalette) private var palette
    let directory: URL
    let roots: [URL]
    let repository: GitRepository?
    @Binding var selectedRoot: URL?
    @Binding var comparison: GitRepository.Comparison?
    let filesVisible: Bool
    let hasFiles: Bool
    let refresh: () -> Void
    let toggleFiles: () -> Void
    @State private var showsRepositories = false
    @State private var showsComparisons = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                repositoryPicker
                Spacer(minLength: 4)
                Button("Refresh Git Changes", systemImage: "arrow.clockwise", action: refresh)
                    .help("Refresh Git Changes")
                Button(filesAction, systemImage: "sidebar.right", action: toggleFiles)
                    .accessibilityLabel(filesAction)
                    .help(filesAction)
                    .disabled(!hasFiles)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            if let repository {
                comparisonControls(repository)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .background(palette.surface)
        .onChange(of: selectedRoot) { showsComparisons = false }
    }

    private var filesAction: String { filesVisible ? "Hide Files" : "Show Files" }

    @ViewBuilder
    private var repositoryPicker: some View {
        if roots.count > 1 {
            ConversationDropdown(isPresented: $showsRepositories, width: 250, arrowEdge: .bottom) {
                ConversationPopoverLabel(title: selectedRoot?.lastPathComponent ?? "Repository")
            } content: {
                Text("Repository").font(.headline)
                ConversationPopoverChoices(count: roots.count) {
                    ForEach(roots, id: \.self) { root in
                        Button {
                            selectedRoot = root
                            showsRepositories = false
                        } label: {
                            ConversationPopoverChoice(title: root.lastPathComponent, selected: root == selectedRoot)
                        }
                        .help(root.path)
                    }
                }
            }
            .help(selectedRoot?.path ?? directory.path)
            .accessibilityLabel("Repository")
            .accessibilityValue(selectedRoot?.lastPathComponent ?? "")
        } else {
            Label(selectedRoot?.lastPathComponent ?? "Git Changes", systemImage: "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(selectedRoot?.path ?? directory.path)
        }
    }

    private func comparisonControls(_ repository: GitRepository) -> some View {
        let selected = comparison ?? repository.defaultComparison
        let title = switch selected {
        case .workingTree: "HEAD · Working changes"
        case .branch(let id): repository.branches.first { $0.id == id }?.name ?? id
        }
        return VStack(alignment: .trailing, spacing: 3) {
            Label(repository.branch, systemImage: "arrow.triangle.branch")
                .lineLimit(1)
                .truncationMode(.middle)
                .help(repository.branch)
                .accessibilityLabel("Current branch \(repository.branch)")
            Text("Compare to").font(.caption2)
            ConversationDropdown(isPresented: $showsComparisons, width: 265, arrowEdge: .bottom) {
                ConversationPopoverLabel(title: title)
            } content: {
                Text("Compare to").font(.headline)
                ConversationPopoverChoices(count: repository.branches.count + 1) {
                    compareOption("Working changes against HEAD", value: .workingTree, current: selected)
                    ForEach(repository.branches) { branch in
                        compareOption(branch.name, value: .branch(branch.id), current: selected)
                    }
                }
            }
            .help(title)
            .accessibilityLabel("Compare to")
            .accessibilityValue(title)
            .accessibilityIdentifier("GitComparison")
        }
        .font(.callout)
        .foregroundStyle(palette.muted)
    }

    private func compareOption(
        _ title: String, value: GitRepository.Comparison, current: GitRepository.Comparison
    ) -> some View {
        Button {
            comparison = value
            showsComparisons = false
        } label: {
            ConversationPopoverChoice(title: title, selected: value == current)
        }
        .help(title)
    }
}
