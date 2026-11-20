import SwiftUI
import SynthClient

struct GitReviewPane: View {
    @Environment(\.synthPalette) private var palette
    let directory: URL
    let turnCompletion: UInt64?
    @State private var repository: GitRepository?
    @State private var requestedComparison: GitRepository.Comparison?
    @State private var changes: GitChanges?
    @State private var selected: GitChangedFile.ID?
    @State private var showsFiles: Bool?
    @State private var paneWidth: CGFloat = 0
    @State private var filter = ""
    @State private var refresh = 0
    @State private var changeVersion = UUID()
    @State private var error: String?
    @State private var loading = true

    private struct Request: Hashable {
        let refresh: Int
        let turnCompletion: UInt64?
        let comparison: GitRepository.Comparison?
    }

    private var request: Request {
        Request(refresh: refresh, turnCompletion: turnCompletion, comparison: requestedComparison)
    }

    private var file: GitChangedFile? { changes?.files.first { $0.id == selected } }
    private var docksFiles: Bool { paneWidth >= 540 }
    private var filesVisible: Bool { showsFiles ?? docksFiles }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            review
        }
        .background(palette.background)
        .foregroundStyle(palette.foreground)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
        .task(id: request) { await loadComparison() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text(repository?.name ?? "Git Changes")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(repository?.root.path ?? directory.path)
                Spacer(minLength: 4)
                Button("Refresh Git Changes", systemImage: "arrow.clockwise") { refresh += 1 }
                    .accessibilityIdentifier("RefreshGitChanges")
                    .help("Refresh Git Changes")
                Button(filesVisible ? "Hide Files" : "Show Files", systemImage: "sidebar.right") {
                    showsFiles = !filesVisible
                }
                .accessibilityLabel(filesVisible ? "Hide Files" : "Show Files")
                .help(filesVisible ? "Hide Files" : "Show Files")
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            if let repository { comparisonControls(repository) }
        }
        .padding(12)
        .background(palette.surface)
    }

    private func comparisonControls(_ repository: GitRepository) -> some View {
        HStack(spacing: 8) {
            Label(repository.branch, systemImage: "arrow.triangle.branch")
                .lineLimit(1)
                .truncationMode(.middle)
                .help(repository.branch)
                .accessibilityLabel("Current branch \(repository.branch)")
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Compare to").font(.caption2)
                Menu {
                    Button {
                        requestedComparison = .workingTree
                    } label: {
                        comparisonOption("Working changes against HEAD", selection: .workingTree)
                    }
                    if !repository.branches.isEmpty {
                        Divider()
                        ForEach(repository.branches) { branch in
                            Button {
                                requestedComparison = .branch(branch.id)
                            } label: {
                                comparisonOption(branch.name, selection: .branch(branch.id))
                            }
                        }
                    }
                } label: {
                    Text(comparisonTitle(in: repository))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .fixedSize(horizontal: false, vertical: true)
                .help("Compare to \(comparisonTitle(in: repository))")
                .accessibilityLabel("Compare to \(comparisonTitle(in: repository))")
                .accessibilityIdentifier("GitComparison")
            }
        }
        .font(.caption)
        .foregroundStyle(palette.muted)
    }

    private func comparisonTitle(in repository: GitRepository) -> String {
        switch requestedComparison ?? repository.defaultComparison {
        case .workingTree: "HEAD · Working changes"
        case .branch(let identifier):
            repository.branches.first { $0.id == identifier }?.name ?? identifier
        }
    }

    private func comparisonOption(_ title: String, selection: GitRepository.Comparison) -> some View {
        let current = requestedComparison ?? repository?.defaultComparison
        return Label(title, systemImage: current == selection ? "checkmark" : "")
    }

    @ViewBuilder
    private var review: some View {
        if loading {
            ProgressView("Reading Git changes…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ContentUnavailableView {
                Label("Git Changes Unavailable", systemImage: "exclamationmark.circle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { refresh += 1 }
            }
        } else if let changes, let file {
            patchAndFiles(changes, file: file)
        } else {
            ContentUnavailableView(
                "No Changed Files",
                systemImage: "checkmark.circle",
                description: Text("The selected comparison has no changes.")
            )
        }
    }

    private func patchAndFiles(_ changes: GitChanges, file: GitChangedFile) -> some View {
        HStack(spacing: 0) {
            GitFilePatchView(changes: changes, file: file, filePicker: !filesVisible, selection: $selected)
                .id(PatchIdentity(version: changeVersion, file: file.id))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if docksFiles && filesVisible { filesList(changes.files) }
        }
        .overlay(alignment: .trailing) {
            if !docksFiles && filesVisible {
                filesList(changes.files).shadow(color: .black.opacity(0.18), radius: 8, x: -3)
            }
        }
    }

    private func filesList(_ files: [GitChangedFile]) -> some View {
        let selection = Binding(get: { selected }, set: { file in
            selected = file
            if !docksFiles { showsFiles = false }
        })
        return HStack(spacing: 0) {
            Divider()
            GitChangedFiles(files: files, selected: selection, filter: $filter)
                .frame(width: 160)
        }
    }

    private struct PatchIdentity: Hashable {
        let version: UUID
        let file: GitChangedFile.ID
    }

    private func loadComparison() async {
        loading = true
        error = nil
        defer { if !Task.isCancelled { loading = false } }
        do {
            let repo = try await gitBackground { [directory] in try GitRepository.discover(at: directory) }
            try Task.checkCancellation()
            repository = repo
            let comparison = requestedComparison ?? repo.defaultComparison
            let result = try await gitBackground { try repo.changes(comparedTo: comparison) }
            try Task.checkCancellation()
            changes = result
            changeVersion = UUID()
            if !result.files.contains(where: { $0.id == selected }) { selected = result.files.first?.id }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

private struct GitChangedFiles: View {
    @Environment(\.synthPalette) private var palette
    let files: [GitChangedFile]
    @Binding var selected: GitChangedFile.ID?
    @Binding var filter: String

    private var visibleFiles: [GitChangedFile] {
        filter.isEmpty ? files : files.filter { $0.path.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Filter files", text: $filter)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter changed files")
            Text("Changed Files (\(files.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.muted)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if visibleFiles.isEmpty {
                        Text("No matching files").font(.caption).foregroundStyle(palette.muted)
                    }
                    ForEach(visibleFiles) { file in
                        fileRow(file)
                    }
                }
            }
        }
        .padding(8)
        .background(palette.surface)
    }

    private func fileRow(_ file: GitChangedFile) -> some View {
        Button {
            selected = file.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text((file.path as NSString).lastPathComponent)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    let directory = (file.path as NSString).deletingLastPathComponent
                    if !directory.isEmpty {
                        Text(directory).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    GitChangeCounts(file: file)
                }
                .font(.caption2)
                .foregroundStyle(palette.muted)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected == file.id ? palette.alternateSurface : .clear, in: .rect(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(file.path)
        .accessibilityAddTraits(selected == file.id ? .isSelected : [])
        .help(file.path)
    }
}

struct GitChangeCounts: View {
    @Environment(\.synthPalette) private var palette
    let file: GitChangedFile

    var body: some View {
        HStack(spacing: 4) {
            if file.isUntracked {
                Text("Untracked")
            } else if file.isBinary {
                Text("Binary")
            } else {
                if let added = file.additions, added > 0 { Text("+\(added)").foregroundStyle(palette.success) }
                if let removed = file.removals, removed > 0 { Text("−\(removed)").foregroundStyle(palette.danger) }
            }
        }
        .monospacedDigit()
        .fixedSize()
    }
}

func gitBackground<Result: Sendable>(_ operation: @escaping @Sendable () throws -> Result) async throws -> Result {
    let work = Task.detached(priority: .userInitiated, operation: operation)
    return try await withTaskCancellationHandler {
        try await work.value
    } onCancel: {
        work.cancel()
    }
}
