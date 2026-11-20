import Foundation

public struct GitPatch: Sendable {
    public struct Hunk: Sendable {
        public let header: String
        public let rows: [SplitDiffRow]
        public let hasMissingNewline: Bool
    }

    public let hunks: [Hunk]
    public let isBinary: Bool

    init(_ patch: Data) {
        var hunks: [Hunk] = []
        var binary = false
        var pending: PendingHunk?
        for raw in patch.split(separator: 10) {
            // swiftlint:disable:next optional_data_string_conversion
            let line = String(decoding: raw, as: UTF8.self)
            if line.hasPrefix("@@ ") {
                if let pending { hunks.append(pending.hunk) }
                pending = PendingHunk(line)
            } else if pending != nil {
                pending?.append(line)
            } else if line.hasPrefix("Binary files ") {
                binary = true
            }
        }
        if let pending { hunks.append(pending.hunk) }
        self.hunks = hunks
        self.isBinary = binary
    }

    private struct PendingHunk {
        let header: String
        var oldNumber: Int
        var newNumber: Int
        var lines: [DiffLine] = []
        var hasMissingNewline = false

        var hunk: Hunk { .init(header: header, rows: SplitDiffRow.pair(lines), hasMissingNewline: hasMissingNewline) }

        init?(_ header: String) {
            let fields = header.split(separator: " ", maxSplits: 4)
            guard fields.count >= 4,
                  let old = Int(fields[1].dropFirst().prefix(while: \.isNumber)),
                  let new = Int(fields[2].dropFirst().prefix(while: \.isNumber)) else { return nil }
            self.header = header
            self.oldNumber = old
            self.newNumber = new
        }

        mutating func append(_ line: String) {
            let text = String(line.dropFirst())
            switch line.first {
            case " ":
                lines.append(.init(kind: .context, text: text, oldNumber: oldNumber, newNumber: newNumber))
                oldNumber += 1
                newNumber += 1
            case "-":
                lines.append(.init(kind: .removal, text: text, oldNumber: oldNumber, newNumber: nil))
                oldNumber += 1
            case "+":
                lines.append(.init(kind: .addition, text: text, oldNumber: nil, newNumber: newNumber))
                newNumber += 1
            case "\\":
                hasMissingNewline = true
            default:
                break
            }
        }
    }
}
