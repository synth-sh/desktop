import SwiftUI
import SynthClient

struct GitReviewPane: View {
    @Environment(\.synthPalette) private var palette
    let directory: URL
    let turnCompletion: UInt64?
    @AppStorage("gitChangedFilesWidth") private var filesWidth = 0.0
    @State private var roots: [URL] = []
    @State private var selectedRoot: URL?
    @State private var comparisons: [URL: GitRepository.Comparison] = [:]
    @State private var repository: GitRepository?
    @State private var changes: GitChanges?
    @State private var selected: GitChangedFile.ID?
    @State private var showsFiles: Bool?
    @State private var paneWidth: CGFloat = 0
    @State private var filter = ""
    @State private var refresh = 0
    @State private var scanVersion = UUID()
    @State private var loadedRequest: ReviewRequest?
    @State private var discoveryError: String?
    @State private var comparisonError: String?
    @State private var scanning = true
    @State private var loading = false

    private struct ScanRequest: Hashable {
        let refresh: Int
        let turnCompletion: UInt64?
    }

    private struct ReviewRequest: Hashable {
        let root: URL
        let comparison: GitRepository.Comparison?
        let version: UUID
    }

    private var reviewRequest: ReviewRequest? {
        selectedRoot.map { ReviewRequest(root: $0, comparison: comparisons[$0], version: scanVersion) }
    }

    private var comparison: Binding<GitRepository.Comparison?> {
        let root = selectedRoot
        return Binding {
            root.flatMap { comparisons[$0] }
        } set: { value in
            if let root { comparisons[root] = value }
        }
    }

    private var docksFiles: Bool { paneWidth >= 555 }
    private var filesVisible: Bool { showsFiles ?? docksFiles }

    var body: some View {
        VStack(spacing: 0) {
            GitReviewHeader(
                directory: directory, roots: roots, repository: repository?.root == selectedRoot ? repository : nil,
                selectedRoot: $selectedRoot, comparison: comparison, filesVisible: filesVisible,
                hasFiles: !scanning && !loading && loadedRequest == reviewRequest && changes?.files.isEmpty == false,
                refresh: { refresh += 1 }, toggleFiles: { showsFiles = !filesVisible }
            )
            Divider()
            review.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .foregroundStyle(palette.foreground)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
        .onChange(of: selectedRoot) {
            selected = nil
            filter = ""
        }
        .task(id: ScanRequest(refresh: refresh, turnCompletion: turnCompletion)) { await scanRepositories() }
        .task(id: reviewRequest) {
            if let request = reviewRequest { await loadComparison(request) }
        }
    }

    @ViewBuilder
    private var review: some View {
        if scanning || (reviewRequest != nil && (loading || loadedRequest != reviewRequest)) {
            ProgressView("Reading Git changes…")
        } else if let error = discoveryError ?? comparisonError {
            ContentUnavailableView {
                Label("Git Changes Unavailable", systemImage: "exclamationmark.circle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { refresh += 1 }
            }
        } else if let changes, let file = changes.files.first(where: { $0.id == selected }) {
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
        let selection = Binding(get: { selected }, set: { file in
            selected = file
            if !docksFiles { showsFiles = false }
        })
        return ResizableTrailingPane(
            savedWidth: $filesWidth, isPresented: filesVisible,
            defaultWidth: 215, minimumWidth: 150, minimumMainWidth: docksFiles ? 275 : 36,
            dividerLabel: "Changed files width", overlaysMain: !docksFiles
        ) {
            GitFilePatchView(changes: changes, file: file, filePicker: !filesVisible, selection: $selected)
                .id(PatchIdentity(request: reviewRequest, file: file.id))
        } pane: {
            GitChangedFiles(files: changes.files, selected: selection, filter: $filter)
        }
    }

    private struct PatchIdentity: Hashable {
        let request: ReviewRequest?
        let file: GitChangedFile.ID
    }

    private func scanRepositories() async {
        scanning = true
        discoveryError = nil
        defer { if !Task.isCancelled { scanning = false } }
        do {
            let found = try await gitBackground { [directory] in try GitRepository.reviewRoots(in: directory) }
            try Task.checkCancellation()
            roots = found
            if selectedRoot.map(found.contains) != true { selectedRoot = found.first }
            scanVersion = UUID()
            if found.isEmpty { discoveryError = GitReviewError.notRepository.localizedDescription }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { discoveryError = error.localizedDescription }
        }
    }

    private func loadComparison(_ request: ReviewRequest) async {
        loadedRequest = request
        loading = true
        comparisonError = nil
        changes = nil
        defer { if !Task.isCancelled { loading = false } }
        do {
            let repo = try await gitBackground { try GitRepository.discover(at: request.root) }
            try Task.checkCancellation()
            repository = repo
            let comparison = request.comparison ?? repo.defaultComparison
            let result = try await gitBackground { try repo.changes(comparedTo: comparison) }
            try Task.checkCancellation()
            changes = result
            if !result.files.contains(where: { $0.id == selected }) { selected = result.files.first?.id }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { comparisonError = error.localizedDescription }
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
                .font(.callout.weight(.semibold))
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
                    .font(.callout.weight(.medium))
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
                .font(.caption)
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
