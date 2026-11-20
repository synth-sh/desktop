import SwiftUI
import SynthClient

struct GitFileBrowser: View {
    @Environment(\.synthPalette) private var palette
    let files: [GitChangedFile]
    let selection: GitChangedFile.ID?
    let choose: (GitChangedFile.ID) -> Void
    @State private var query = ""
    @State private var highlight: GitChangedFile.ID?

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = needle.isEmpty ? files : files.filter { $0.path.localizedCaseInsensitiveContains(needle) }
        let active = matches.first { $0.id == highlight }
            ?? (needle.isEmpty ? matches.first { $0.id == selection } : nil) ?? matches.first

        VStack(alignment: .leading, spacing: 9) {
            Text("Changed Files").font(.headline)
            PopoverSearchField(
                text: $query, placeholder: "Filter files", label: "Filter changed files",
                autofocus: true,
                move: { move($0, from: active?.id, in: matches) },
                submit: { if let active { choose(active.id) } }
            )
            .frame(height: 22)
            if matches.isEmpty {
                Text("No matching files").font(.callout).foregroundStyle(palette.muted)
            } else {
                results(matches, active: active?.id)
            }
        }
        .onChange(of: query) { highlight = nil }
    }

    private func results(_ files: [GitChangedFile], active: GitChangedFile.ID?) -> some View {
        ScrollViewReader { reader in
            ConversationPopoverChoices(count: files.count) {
                ForEach(files) { file in
                    Button {
                        choose(file.id)
                    } label: {
                        ConversationPopoverChoice(title: file.path, selected: selection == file.id)
                            .font(.body)
                    }
                    .background(active == file.id ? palette.alternateSurface : .clear, in: .rect(cornerRadius: 5))
                    .help(file.path)
                    .id(file.id)
                }
            }
            .onChange(of: active, initial: true) {
                if let active { reader.scrollTo(active) }
            }
        }
    }

    private func move(_ offset: Int, from active: GitChangedFile.ID?, in files: [GitChangedFile]) {
        guard let index = files.firstIndex(where: { $0.id == active }) else { return }
        highlight = files[min(max(index + offset, 0), files.count - 1)].id
    }
}
