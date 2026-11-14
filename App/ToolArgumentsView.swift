import SwiftUI

struct ToolArgumentsView: View {
    let arguments: String
    let showsDiff: Bool
    var title: String?

    var body: some View {
        Group {
            if showsDiff, let change = ToolChange(arguments: arguments), !change.lines.isEmpty {
                ToolDiffView(change: change)
            } else {
                if let title { Text(title).font(.body).textSelection(.enabled) }
                Text(arguments).textSelection(.enabled)
            }
        }
        .font(.system(.caption, design: .monospaced))
    }
}

private struct ToolChange {
    enum Line: Equatable {
        case context(String), removed(String), added(String)

        var text: String {
            switch self {
            case .context(let text): "  " + text
            case .removed(let text): "- " + text
            case .added(let text): "+ " + text
            }
        }
    }

    let title: String
    let lines: [Line]

    init?(arguments: String) {
        guard let input = try? JSONDecoder().decode([String: String].self, from: Data(arguments.utf8)),
              let path = input["path"] else { return nil }
        if input.count == 3, let old = input["old"], let new = input["new"] {
            title = "Edit \(path)"
            lines = Self.diff(old: Self.splitLines(old), new: Self.splitLines(new))
        } else if input.count == 2, let content = input["content"] {
            title = "Write \(path)"
            lines = Self.splitLines(content).map(Line.added)
        } else {
            return nil
        }
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return (text.last?.isNewline == true ? lines.dropLast() : lines[...]).map(String.init)
    }

    private static func diff(old: [String], new: [String]) -> [Line] {
        guard old != new else { return [] }
        // Limit the diff algorithm as in the TUI; large inputs are shown as replacements.
        guard old.count <= 400, new.count <= 400 else { return old.map(Line.removed) + new.map(Line.added) }
        var removed: Set<Int> = []
        var added: Set<Int> = []
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }

        var lines: [Line] = []
        var before = 0
        var after = 0
        while before < old.count || after < new.count {
            if removed.contains(before) {
                lines.append(.removed(old[before]))
                before += 1
            } else if added.contains(after) {
                lines.append(.added(new[after]))
                after += 1
            } else {
                lines.append(.context(new[after]))
                before += 1
                after += 1
            }
        }
        return lines
    }
}

private struct ToolDiffView: View {
    @Environment(\.synthPalette) private var palette
    let change: ToolChange

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(change.title)
                .foregroundStyle(palette.foreground)
                .textSelection(.enabled)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(change.lines.indices, id: \.self) { index in
                    let line = change.lines[index]
                    let colors = colors(for: line)
                    Text(line.text)
                        .foregroundStyle(colors.foreground)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.background)
                        .textSelection(.enabled)
                }
            }
            .clipShape(.rect(cornerRadius: 5))
        }
    }

    private func colors(for line: ToolChange.Line) -> (foreground: Color, background: Color) {
        switch line {
        case .context: (palette.foreground, palette.background)
        case .removed: (palette.diffRemovedForeground, palette.diffRemovedBackground)
        case .added: (palette.diffAddedForeground, palette.diffAddedBackground)
        }
    }
}
