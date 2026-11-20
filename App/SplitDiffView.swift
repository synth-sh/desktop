import SwiftUI
import SynthClient

struct SplitDiffView: View {
    @Environment(\.synthPalette) private var palette
    let path: String
    let rows: [SplitDiffRow]

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                HStack(alignment: .top, spacing: 1) {
                    side(row.old, number: row.old?.oldNumber)
                    side(row.new, number: row.new?.newNumber)
                }
                .background {
                    HStack(spacing: 1) {
                        row.old?.kind.diffBackground(palette) ?? palette.surface
                        row.new?.kind.diffBackground(palette) ?? palette.surface
                    }
                    .background(palette.border)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .accessibilityIdentifier("SplitDiff")
    }

    private func side(_ line: DiffLine?, number: Int?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            DiffGutter(number: number)
            if let line { DiffCodeLine(line: line, path: path) }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 18, alignment: .topLeading)
    }
}

struct AddedFileLines: View {
    @Environment(\.synthPalette) private var palette
    let path: String
    let lines: [DiffLine]

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
                let line = lines[index]
                HStack(alignment: .top, spacing: 0) {
                    DiffGutter(number: line.newNumber)
                    DiffCodeLine(line: line, path: path)
                }
                .background(palette.diffAddedBackground)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .accessibilityIdentifier("AddedFileLines")
    }
}

struct DiffGutter: View {
    @Environment(\.synthPalette) private var palette
    let number: Int?

    var body: some View {
        Text(number.map(String.init) ?? "")
            .foregroundStyle(palette.muted)
            .padding(.vertical, 2)
            .frame(minWidth: 32, alignment: .trailing)
            .padding(.trailing, 5)
    }
}

struct DiffCodeLine: View {
    @Environment(\.synthPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    let line: DiffLine
    let path: String

    var body: some View {
        let text = line.text.last == "\r" ? String(line.text.dropLast()) : line.text
        HStack(alignment: .top, spacing: 5) {
            Text(sign).accessibilityHidden(true)
            code(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(line.kind.diffForeground(palette))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private var sign: String {
        switch line.kind {
        case .context: " "
        case .removal: "−"
        case .addition: "+"
        }
    }

    private func code(_ text: String) -> Text {
        if let highlighted = MarkdownPresentation.highlightedLine(text, path: path, colorScheme: colorScheme) {
            return Text(highlighted)
        }
        return Text(verbatim: text.isEmpty ? " " : text)
    }
}

extension DiffLine.Kind {
    func diffBackground(_ palette: SynthPalette) -> Color {
        switch self {
        case .context: palette.background
        case .removal: palette.diffRemovedBackground
        case .addition: palette.diffAddedBackground
        }
    }

    func diffForeground(_ palette: SynthPalette) -> Color {
        switch self {
        case .context: palette.foreground
        case .removal: palette.diffRemovedForeground
        case .addition: palette.diffAddedForeground
        }
    }
}
