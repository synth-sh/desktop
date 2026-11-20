import SwiftUI
import SynthClient

struct GitFilePatchView: View {
    @Environment(\.synthPalette) private var palette
    let changes: GitChanges
    let file: GitChangedFile
    let filePicker: Bool
    @Binding var selection: GitChangedFile.ID?
    @State private var patch: GitPatch?
    @State private var error: String?
    @State private var showsFilePicker = false
    @State private var showsActions = false

    var body: some View {
        VStack(spacing: 0) {
            fileHeader
            Divider()
            patchBody
        }
        .task { await loadPatch() }
    }

    private var fileHeader: some View {
        HStack(spacing: 7) {
            if filePicker {
                ConversationDropdown(isPresented: $showsFilePicker, width: 330, arrowEdge: .bottom) {
                    ConversationPopoverLabel(title: file.path)
                        .font(.callout.weight(.medium))
                } content: {
                    GitFileBrowser(files: changes.files, selection: selection) { identifier in
                        selection = identifier
                        showsFilePicker = false
                    }
                }
                .accessibilityIdentifier("GitFilePicker")
                .help(file.path)
            } else {
                Label(file.path, systemImage: "doc.text")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)
            }
            Spacer(minLength: 2)
            GitChangeCounts(file: file)
                .foregroundStyle(palette.muted)
            fileMenu
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surface.opacity(0.6))
    }

    private var fileMenu: some View {
        ConversationDropdown(isPresented: $showsActions, width: 185, arrowEdge: .bottom) {
            Image(systemName: "ellipsis")
                .padding(.horizontal, 3)
        } content: {
            let url = changes.existingFileURL(for: file)
            VStack(spacing: 3) {
                Button("Open in Editor", systemImage: "arrow.up.forward.app") {
                    showsActions = false
                    if let url { NSWorkspace.shared.open(url) }
                }
                .disabled(url == nil)
                Button("Copy Path", systemImage: "document.on.document") {
                    showsActions = false
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(file.path, forType: .string)
                }
            }
            .buttonStyle(ConversationPopoverRowStyle())
        }
        .fixedSize()
        .accessibilityLabel("File Actions")
        .help("File Actions")
    }

    @ViewBuilder
    private var patchBody: some View {
        if let patch, !patch.hunks.isEmpty {
            if !patch.isNewFile { columns }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(patch.hunks.indices, id: \.self) { index in
                        let hunk = patch.hunks[index]
                        if patch.isNewFile {
                            AddedFileLines(path: file.path, lines: hunk.rows.compactMap(\.new))
                        } else {
                            hunkNote(hunk.header)
                            SplitDiffView(path: file.path, rows: hunk.rows)
                        }
                        if hunk.hasMissingNewline { hunkNote("No newline at end of file") }
                    }
                }
            }
        } else if let error {
            ContentUnavailableView(
                "Couldn't Read Diff", systemImage: "exclamationmark.circle", description: Text(error)
            )
        } else if let patch {
            ContentUnavailableView(emptyTitle(for: patch), systemImage: "doc")
        } else {
            ProgressView("Reading diff…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func emptyTitle(for patch: GitPatch) -> String {
        if patch.isBinary || file.isBinary { return "Binary File" }
        return patch.isNewFile ? "Empty New File" : "No Text Changes"
    }

    private var columns: some View {
        HStack(spacing: 1) {
            Text("Before").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
            Text("After").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(palette.muted)
        .padding(.vertical, 5)
        .background(palette.surface)
    }

    private func hunkNote(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(palette.muted)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(palette.alternateSurface)
    }

    private func loadPatch() async {
        error = nil
        do {
            let result = try await gitBackground { [changes, file] in try changes.patch(for: file) }
            try Task.checkCancellation()
            patch = result
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
