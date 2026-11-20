import Foundation

public struct ToolFileChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case context, removal, addition }

    public struct Line: Equatable, Sendable {
        public let kind: Kind
        public let text: String
        public let oldNumber: Int?
        public let newNumber: Int?
    }

    public struct Hunk: Equatable, Sendable {
        public let lines: [Line]
    }

    public let path: String
    public let hunks: [Hunk]

    public init?(arguments: String, result: String? = nil) {
        struct Replacement: Decodable {
            let old: String
            let new: String
        }
        struct Input: Decodable {
            let path: String
            let content: String?
            let old: String?
            let new: String?
            let edits: [Replacement]?
        }

        guard let input = try? JSONDecoder().decode(Input.self, from: Data(arguments.utf8)),
              !input.path.isEmpty else { return nil }
        path = input.path
        if let content = input.content, input.edits == nil, input.old == nil, input.new == nil {
            hunks = [Self.hunk(old: "", new: content, start: 1)]
        } else if let edits = input.edits, !edits.isEmpty, input.old == nil, input.new == nil, input.content == nil {
            let start = edits.count == 1 ? Self.reportedStart(result, path: input.path) : nil
            hunks = edits.map { Self.hunk(old: $0.old, new: $0.new, start: start) }
        } else if let old = input.old, let new = input.new, input.edits == nil, input.content == nil {
            hunks = [Self.hunk(old: old, new: new, start: Self.reportedStart(result, path: input.path))]
        } else {
            return nil
        }
    }

    private static func reportedStart(_ result: String?, path: String) -> Int? {
        let prefix = "edited \(path) at line "
        guard let result, result.hasPrefix(prefix),
              let line = Int(result.dropFirst(prefix.count)), line > 0 else { return nil }
        return line
    }

    private static func hunk(old: String, new: String, start: Int?) -> Hunk {
        let before = splitLines(old)
        let after = splitLines(new)
        guard old != new else { return Hunk(lines: []) }
        // Keep the longest common subsequence bounded for whole-file replacements.
        let changes = before.count <= 400 && after.count <= 400 ? after.difference(from: before) : nil
        var removed: Set<Int> = []
        var added: Set<Int> = []
        if let changes {
            for change in changes {
                switch change {
                case .remove(let offset, _, _): removed.insert(offset)
                case .insert(let offset, _, _): added.insert(offset)
                }
            }
            if before == after, let last = before.indices.last {
                removed.insert(last)
                added.insert(last)
            }
        }

        var lines: [Line] = []
        var left = 0
        var right = 0
        while left < before.count || right < after.count {
            if left < before.count, changes == nil || removed.contains(left) {
                lines.append(.init(kind: .removal, text: before[left], oldNumber: number(start, left), newNumber: nil))
                left += 1
            } else if right < after.count, changes == nil || added.contains(right) {
                lines.append(.init(kind: .addition, text: after[right],
                                   oldNumber: nil, newNumber: number(start, right)))
                right += 1
            } else {
                lines.append(.init(kind: .context, text: after[right],
                                   oldNumber: number(start, left), newNumber: number(start, right)))
                left += 1
                right += 1
            }
        }
        return Hunk(lines: lines)
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.utf8.last == 10 { lines.removeLast() }
        return lines
    }

    private static func number(_ start: Int?, _ offset: Int) -> Int? {
        guard let start, offset <= Int.max - start else { return nil }
        return start + offset
    }
}
