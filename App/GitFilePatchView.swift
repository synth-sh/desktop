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
    @State private var collapsed = false

    var body: some View {
        VStack(spacing: 0) {
            fileHeader
            Divider()
            if collapsed {
                Button("Expand Diff", systemImage: "chevron.down") { collapsed = false }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                patchBody
            }
        }
        .task(id: collapsed) { if !collapsed, patch == nil { await loadPatch() } }
    }

    private var fileHeader: some View {
        HStack(spacing: 7) {
            if filePicker {
                Menu {
                    ForEach(changes.files) { candidate in
                        Button(candidate.path) { selection = candidate.id }
                    }
                } label: {
                    Label(file.path, systemImage: "doc.text")
                        .lineLimit(1)
                        .truncationMode(.middle)
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
        Menu {
            Button(collapsed ? "Expand" : "Collapse") { collapsed.toggle() }
            Button("Open in Editor") {
                if let url = changes.existingFileURL(for: file) { NSWorkspace.shared.open(url) }
            }
            .disabled(changes.existingFileURL(for: file) == nil)
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        } label: {
            Image(systemName: "ellipsis")
                .padding(.horizontal, 3)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("File Actions")
        .help("File Actions")
    }

    @ViewBuilder
    private var patchBody: some View {
        if let patch, !patch.hunks.isEmpty {
            columns
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(patch.hunks.indices, id: \.self) { index in
                        let hunk = patch.hunks[index]
                        hunkNote(hunk.header)
                        SplitDiffView(path: file.path, rows: hunk.rows)
                        if hunk.hasMissingNewline { hunkNote("No newline at end of file") }
                    }
                }
            }
        } else if let error {
            ContentUnavailableView(
                "Couldn't Read Diff", systemImage: "exclamationmark.circle", description: Text(error)
            )
        } else if let patch {
            ContentUnavailableView(
                patch.isBinary || file.isBinary ? "Binary File" : "No Text Changes",
                systemImage: "doc"
            )
        } else {
            ProgressView("Reading diff…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
