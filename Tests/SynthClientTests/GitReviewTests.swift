import Foundation
import SynthClient
import Testing

@Test func comparesCommittedFilesAndWorkingChangesSeparately() throws {
    let fixture = try GitReviewFixture()
    defer { fixture.remove() }
    try fixture.write("before\nshared\n", to: "App/Example.swift")
    try fixture.write("removed\n", to: "Old file.txt")
    try fixture.git("add", ".")
    try fixture.git("commit", "-qm", "Base")
    try fixture.git("update-ref", "refs/remotes/origin/main", "HEAD")
    try fixture.git("switch", "-qc", "feature/review")
    try fixture.write("after\nshared\n", to: "App/Example.swift")
    try fixture.git("rm", "-q", "Old file.txt")
    try Data([0, 1, 2]).write(to: fixture.root.appending(path: "Binary.dat"))
    try fixture.git("add", ".")
    try fixture.git("commit", "-qm", "Feature")
    try fixture.write("working\nshared\n", to: "App/Example.swift")
    try fixture.write("staged\n", to: "New staged.txt")
    try fixture.git("add", "New staged.txt")
    try fixture.write("note\n", to: ":notes\tfile.txt")

    let repo = try GitRepository.discover(at: fixture.root.appending(path: "App"))
    #expect(repo.root.path == fixture.root.path)
    #expect(repo.branch == "feature/review")
    #expect(repo.defaultComparison == .branch("refs/remotes/origin/main"))
    let committed = try repo.changes(comparedTo: repo.defaultComparison)
    #expect(Set(committed.files.map(\.path)) == ["App/Example.swift", "Old file.txt", "Binary.dat"])
    let tracked = try #require(committed.files.first { $0.path == "App/Example.swift" })
    let trackedPatch = try committed.patch(for: tracked)
    #expect(!trackedPatch.isNewFile)
    let hunk = try #require(trackedPatch.hunks.first)
    #expect(hunk.rows.first?.old?.text == "before")
    #expect(hunk.rows.first?.new?.text == "after")
    #expect(hunk.rows.last?.new?.newNumber == 2)
    let deleted = try #require(committed.files.first { $0.path == "Old file.txt" })
    #expect(committed.existingFileURL(for: deleted) == nil)
    let binary = try #require(committed.files.first { $0.path == "Binary.dat" })
    #expect(binary.isBinary)
    #expect(try committed.patch(for: binary).isBinary)

    let working = try repo.changes(comparedTo: .workingTree)
    #expect(Set(working.files.map(\.path)) == ["App/Example.swift", "New staged.txt", ":notes\tfile.txt"])
    let untracked = try #require(working.files.first { $0.isUntracked })
    let untrackedPatch = try working.patch(for: untracked)
    #expect(untrackedPatch.isNewFile)
    #expect(untrackedPatch.hunks.first?.rows.first?.old == nil)
    #expect(untrackedPatch.hunks.first?.rows.first?.new?.text == "note")
    #expect(working.existingFileURL(for: untracked)?.lastPathComponent == untracked.path)
}

@Test func opensUnbornWorkingTreeAndDisablesRepositoryCleanFilters() throws {
    let fixture = try GitReviewFixture()
    defer { fixture.remove() }
    try fixture.write("*.txt filter=fixture\n", to: ".gitattributes")
    try fixture.write("staged", to: "Draft.txt")
    try fixture.git("add", ".")
    try fixture.git("config", "filter.fixture.clean", "touch filter-ran; cat")
    try fixture.git("config", "filter.fixture.required", "true")
    try fixture.write("unstaged", to: "Draft.txt")

    let repository = try GitRepository.discover(at: fixture.root)
    #expect(repository.defaultComparison == .workingTree)
    let changes = try repository.changes(comparedTo: .workingTree)
    let draft = try #require(changes.files.first { $0.path == "Draft.txt" })
    let patch = try changes.patch(for: draft)
    #expect(patch.isNewFile)
    #expect(patch.hunks.first?.rows.first?.new?.text == "unstaged")
    #expect(patch.hunks.first?.hasMissingNewline == true)
    #expect(!FileManager.default.fileExists(atPath: fixture.root.appending(path: "filter-ran").path))
}

@Test func discoversImmediateRepositoriesIncludingLinkedWorktrees() throws {
    let parent = FileManager.default.temporaryDirectory.appending(path: "SynthGitParent-" + UUID().uuidString)
        .resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: parent) }
    let repository = try GitReviewFixture(root: parent.appending(path: "First", directoryHint: .isDirectory))
    try repository.write("ready\n", to: "README.md")
    try repository.git("add", ".")
    try repository.git("commit", "-qm", "Start")
    let linked = parent.appending(path: "Second", directoryHint: .isDirectory)
    try repository.git("worktree", "add", "--quiet", "--detach", linked.path)
    _ = try GitReviewFixture(root: parent.appending(path: "Group/TooDeep", directoryHint: .isDirectory))
    _ = try GitReviewFixture(root: repository.root.appending(path: "Inner", directoryHint: .isDirectory))

    let choices = try GitRepository.reviewRoots(in: parent)
    #expect(choices.map(\.lastPathComponent) == ["First", "Second"])
    #expect(try GitRepository.discover(at: linked).root.path == linked.path)
    let nested = try GitRepository.reviewRoots(in: repository.root)
    #expect(nested.map(\.lastPathComponent) == ["First", "Inner"])
}

private struct GitReviewFixture {
    let root: URL

    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.temporaryDirectory.appending(path: "SynthGit-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func write(_ text: String, to path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func git(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = root
        process.arguments = [
            "-c", "user.name=Fixture", "-c", "user.email=fixture@example.com",
            "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"
        ] + arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "Fixture git \(arguments) failed")
    }
}
