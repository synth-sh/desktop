import Foundation

public struct GitRepository: Sendable {
    public enum Comparison: Hashable, Sendable {
        case workingTree
        case branch(String)
    }

    public struct Branch: Identifiable, Sendable {
        public let id: String
        public let name: String
        fileprivate let revision: String
    }

    public let root: URL
    public let branch: String
    public let branches: [Branch]
    public let defaultComparison: Comparison
    private let head: String?

    public var name: String { root.lastPathComponent }

    public static func discover(at directory: URL) throws -> Self {
        let location = GitCommand(directory: directory)
        guard let path = try location.optionalText(["rev-parse", "--show-toplevel"], missing: 128) else {
            throw GitReviewError.notRepository
        }
        let root = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
        let git = GitCommand(directory: root)
        let head = try git.optionalText(["rev-parse", "--verify", "HEAD"], missing: 128)
        let current = try git.optionalText(["symbolic-ref", "--quiet", "HEAD"], missing: 1)
        let upstreamHead = try git.optionalText(["symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"], missing: 1)
        let branches = try reviewBranches(git, excluding: current)

        let preferred = ([upstreamHead].compactMap { $0 } + [
            "refs/remotes/origin/main", "refs/remotes/origin/master", "refs/remotes/origin/trunk",
            "refs/heads/main", "refs/heads/master", "refs/heads/trunk"
        ]).compactMap { ref in branches.first { $0.id == ref } }.first
        let comparison: Comparison = if let head, let preferred, preferred.revision != head,
                                        !isDefaultBranch(current, preferred: preferred) {
            .branch(preferred.id)
        } else {
            .workingTree
        }
        return Self(
            root: root, branch: current.map(displayName) ?? head.map { "Detached at " + $0.prefix(7) } ?? "Unborn HEAD",
            branches: branches, defaultComparison: comparison, head: head
        )
    }

    private static func reviewBranches(_ git: GitCommand, excluding current: String?) throws -> [Branch] {
        let output = try git.run(["for-each-ref", "--format=%(refname)%00%(objectname)", "refs/heads", "refs/remotes"])
        return output.split(separator: 10).compactMap { record in
            let fields = record.split(separator: 0, maxSplits: 1).compactMap { String(bytes: $0, encoding: .utf8) }
            guard fields.count == 2, fields[0] != current,
                  !fields[0].hasPrefix("refs/remotes/") || !fields[0].hasSuffix("/HEAD") else { return nil }
            return Branch(id: fields[0], name: displayName(fields[0]), revision: fields[1])
        }
    }

    private static func displayName(_ ref: String) -> String {
        if ref.hasPrefix("refs/heads/") { return String(ref.dropFirst("refs/heads/".count)) }
        return String(ref.dropFirst("refs/remotes/".count))
    }

    private static func isDefaultBranch(_ current: String?, preferred: Branch) -> Bool {
        guard let current else { return false }
        let name = displayName(current)
        return ["main", "master", "trunk"].contains(name) || preferred.name == "origin/" + name
    }

    public func changes(comparedTo comparison: Comparison) throws -> GitChanges {
        let git = GitCommand(directory: root)
        let revisions: [String]
        let filters: [String]
        switch comparison {
        case .workingTree:
            revisions = [try head ?? git.text(["hash-object", "-t", "tree", "/dev/null"])]
            filters = try git.disabledFilters()
        case .branch(let ref):
            guard let head, let base = branches.first(where: { $0.id == ref }),
                  let ancestor = try git.optionalText(["merge-base", base.revision, head], missing: 1) else {
                throw GitReviewError.unrelatedBranches
            }
            revisions = [ancestor, head]
            filters = []
        }
        let stats = try git.run(filters + GitChanges.diffOptions + ["--numstat", "-z"] + revisions + ["--"])
        var files = GitChangedFile.parseNumstat(stats)
        if comparison == .workingTree {
            let untracked = try git.run(["ls-files", "--others", "--exclude-standard", "-z"])
            files += untracked.split(separator: 0).compactMap(GitChangedFile.untracked)
        }
        files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return GitChanges(root: root, comparison: comparison, files: files, revisions: revisions, filters: filters)
    }
}

public struct GitChanges: Sendable {
    public let root: URL
    public let comparison: GitRepository.Comparison
    public let files: [GitChangedFile]
    fileprivate let revisions: [String]
    fileprivate let filters: [String]

    static let diffOptions = [
        "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames", "--no-relative",
        "--word-diff=none", "--ignore-submodules=dirty"
    ]

    public func patch(for file: GitChangedFile) throws -> GitPatch {
        let git = GitCommand(directory: root)
        var arguments = filters + Self.diffOptions + ["--patch", "--unified=3"]
        if file.isUntracked {
            arguments += ["--no-index", "--", "/dev/null", "./" + file.path]
        } else {
            arguments += revisions + ["--", file.path]
        }
        let result = try git.run(arguments, limit: 2 * 1_024 * 1_024, acceptsChanges: file.isUntracked)
        return GitPatch(result)
    }

    public func existingFileURL(for file: GitChangedFile) -> URL? {
        let candidate = root.appending(path: file.path, directoryHint: .notDirectory).resolvingSymlinksInPath()
        let prefix = root.path == "/" ? "/" : root.path + "/"
        guard candidate.path.hasPrefix(prefix),
              (try? candidate.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        return candidate
    }
}

public struct GitChangedFile: Identifiable, Sendable {
    public struct Identifier: Hashable, Sendable {
        let path: String
        let untracked: Bool
    }

    public let path: String
    public let additions: Int?
    public let removals: Int?
    public let isUntracked: Bool

    public var isBinary: Bool { !isUntracked && additions == nil && removals == nil }
    public var id: Identifier { Identifier(path: path, untracked: isUntracked) }

    fileprivate static func parseNumstat(_ bytes: Data) -> [Self] {
        bytes.split(separator: 0).compactMap { record in
            let fields = record.split(separator: 9, maxSplits: 2)
            guard fields.count == 3,
                  let plus = String(bytes: fields[0], encoding: .utf8),
                  let minus = String(bytes: fields[1], encoding: .utf8),
                  let path = String(bytes: fields[2], encoding: .utf8),
                  !path.isEmpty else { return nil }
            return Self(path: path, additions: Int(plus), removals: Int(minus), isUntracked: false)
        }
    }

    fileprivate static func untracked(_ record: Data.SubSequence) -> Self? {
        guard let path = String(bytes: record, encoding: .utf8), !path.isEmpty, !path.hasSuffix("/") else { return nil }
        return Self(path: path, additions: nil, removals: nil, isUntracked: true)
    }
}

public enum GitReviewError: LocalizedError {
    case notRepository
    case unrelatedBranches
    case readFailed
    case outputTooLarge

    public var errorDescription: String? {
        switch self {
        case .notRepository: "This folder is outside a Git working tree."
        case .unrelatedBranches: "The current checkout and this comparison branch have no common commit."
        case .readFailed: "Git could not read this comparison."
        case .outputTooLarge: "This Git output is too large to display."
        }
    }
}
