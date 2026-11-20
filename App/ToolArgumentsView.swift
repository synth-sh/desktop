import SwiftUI
import SynthClient

struct ToolArgumentsView: View {
    let arguments: String
    let showsDiff: Bool
    var title: String?
    var result: String?
    var applied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsDiff, let change = ToolFileChange(arguments: arguments, result: applied ? result : nil) {
                ToolDiffView(change: change, applied: applied)
            } else if let title {
                Text(title).font(.body).textSelection(.enabled)
            }
            if !arguments.isEmpty {
                ActivityDisclosure(title: "Arguments") {
                    Text(verbatim: arguments)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct ToolDiffView: View {
    @Environment(\.synthPalette) private var palette
    let change: ToolFileChange
    let applied: Bool
    @State private var showAll = false
    private let previewCount = 14

    private var lineCount: Int { change.hunks.reduce(0) { $0 + $1.lines.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                Text(change.path).lineLimit(1).truncationMode(.middle).help(change.path)
                Spacer()
                if !applied { Text("Proposed").foregroundStyle(palette.muted) }
            }
            .font(.caption.weight(.medium))
            if lineCount == 0 {
                Text("No changed lines").font(.caption).foregroundStyle(palette.muted)
            } else {
                ForEach(visibleHunks, id: \.offset) { _, lines in
                    hunk(lines)
                }
            }
            if lineCount > previewCount {
                Button(showAll ? "Show Less" : "Show Full Diff (\(lineCount) lines)") { showAll.toggle() }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(10)
        .background(palette.surface, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border).allowsHitTesting(false) }
    }

    private var visibleHunks: [(offset: Int, lines: ArraySlice<ToolFileChange.Line>)] {
        var remaining = showAll ? lineCount : previewCount
        return change.hunks.enumerated().compactMap { index, hunk in
            let lines = hunk.lines.prefix(remaining)
            remaining -= lines.count
            return lines.isEmpty ? nil : (offset: index, lines: lines)
        }
    }

    private func hunk(_ lines: ArraySlice<ToolFileChange.Line>) -> some View {
        ViewThatFits(in: .horizontal) {
            SplitDiffView(path: change.path, rows: SplitDiffRow.pair(lines)).frame(minWidth: 560)
            unified(lines)
        }
        .clipShape(.rect(cornerRadius: 5))
        .font(.system(.caption, design: .monospaced))
    }

    private func unified(_ lines: ArraySlice<ToolFileChange.Line>) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
                let line = lines[index]
                HStack(alignment: .top, spacing: 0) {
                    DiffGutter(number: line.oldNumber)
                    DiffGutter(number: line.newNumber)
                    DiffCodeLine(line: line, path: change.path)
                }
                .background(line.kind.diffBackground(palette))
            }
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("UnifiedDiff")
    }
}
