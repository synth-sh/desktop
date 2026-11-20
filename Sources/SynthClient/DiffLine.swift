public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case context, removal, addition }

    public let kind: Kind
    public let text: String
    public let oldNumber: Int?
    public let newNumber: Int?
}

public struct SplitDiffRow: Equatable, Sendable {
    public let old: DiffLine?
    public let new: DiffLine?

    public static func pair(_ lines: some Collection<DiffLine>) -> [Self] {
        var rows: [Self] = []
        var removed: [DiffLine] = []
        var added: [DiffLine] = []

        func flush() {
            for index in 0..<max(removed.count, added.count) {
                rows.append(Self(
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
                rows.append(.init(old: line, new: line))
            case .removal: removed.append(line)
            case .addition: added.append(line)
            }
        }
        flush()
        return rows
    }
}
