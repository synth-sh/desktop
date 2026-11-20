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
    @Environment(\.colorScheme) private var colorScheme
    let change: ToolFileChange
    let applied: Bool
    @State private var showAll = false
    private let previewCount = 14

    private struct Pair {
        let old: ToolFileChange.Line?
        let new: ToolFileChange.Line?
    }

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
            split(lines).frame(minWidth: 560)
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
                    gutter(line.oldNumber)
                    gutter(line.newNumber)
                    code(line)
                }
                .background(background(for: line.kind))
            }
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("UnifiedDiff")
    }

    private func split(_ lines: ArraySlice<ToolFileChange.Line>) -> some View {
        let pairs = sideBySide(lines)
        return LazyVStack(spacing: 0) {
            ForEach(pairs.indices, id: \.self) { index in
                let pair = pairs[index]
                HStack(alignment: .top, spacing: 1) {
                    side(pair.old, number: pair.old?.oldNumber)
                    side(pair.new, number: pair.new?.newNumber)
                }
                .background(palette.border)
            }
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("SplitDiff")
    }

    private func sideBySide(_ lines: ArraySlice<ToolFileChange.Line>) -> [Pair] {
        var pairs: [Pair] = []
        var removed: [ToolFileChange.Line] = []
        var added: [ToolFileChange.Line] = []
        func flush() {
            for index in 0..<max(removed.count, added.count) {
                pairs.append(Pair(
                    old: index < removed.count ? removed[index] : nil,
                    new: index < added.count ? added[index] : nil
                ))
            }
            removed.removeAll(keepingCapacity: true)
            added.removeAll(keepingCapacity: true)
        }
        for line in lines {
            switch line.kind {
            case .context:
                flush()
                pairs.append(.init(old: line, new: line))
            case .removal: removed.append(line)
            case .addition: added.append(line)
            }
        }
        flush()
        return pairs
    }

    private func side(_ line: ToolFileChange.Line?, number: Int?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            gutter(number)
            if let line { code(line) } else { Color.clear.frame(height: 18) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.map { background(for: $0.kind) } ?? palette.surface)
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .foregroundStyle(palette.muted)
            .padding(.vertical, 2)
            .frame(minWidth: 36, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private func code(_ line: ToolFileChange.Line) -> some View {
        let sign = switch line.kind {
        case .context: " "
        case .removal: "−"
        case .addition: "+"
        }
        let color = switch line.kind {
        case .context: palette.foreground
        case .removal: palette.diffRemovedForeground
        case .addition: palette.diffAddedForeground
        }
        return HStack(alignment: .top, spacing: 5) {
            Text(sign).accessibilityHidden(true)
            codeText(line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func codeText(_ text: String) -> Text {
        if let highlighted = MarkdownPresentation.highlightedLine(text, path: change.path, colorScheme: colorScheme) {
            return Text(highlighted)
        }
        return Text(verbatim: text.isEmpty ? " " : text)
    }

    private func background(for kind: ToolFileChange.Kind) -> Color {
        switch kind {
        case .context: palette.background
        case .removal: palette.diffRemovedBackground
        case .addition: palette.diffAddedBackground
        }
    }
}
