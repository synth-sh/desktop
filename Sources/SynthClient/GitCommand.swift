import Foundation

struct GitCommand {
    let directory: URL

    func text(_ arguments: [String]) throws -> String {
        guard let value = try optionalText(arguments) else { throw GitReviewError.readFailed }
        return value
    }

    func optionalText(_ arguments: [String], missing: Int32? = nil) throws -> String? {
        let output = try run(arguments, missing: missing)
        guard let value = String(bytes: output, encoding: .utf8), !value.isEmpty else { return nil }
        return value.last == "\n" ? String(value.dropLast()) : value
    }

    func disabledFilters() throws -> [String] {
        let names = try run(["config", "--null", "--name-only", "--get-regexp", "^filter\\."], missing: 1)
        let keys = Set(names.split(separator: 0).compactMap { String(bytes: $0, encoding: .utf8) })
        return keys.sorted().flatMap { key -> [String] in
            // Working-tree diffs can invoke clean filters even with text conversion disabled.
            if key.hasSuffix(".clean") || key.hasSuffix(".process") { return ["-c", key + "="] }
            if key.hasSuffix(".required") { return ["-c", key + "=false"] }
            return []
        }
    }

    func run(
        _ arguments: [String], limit: Int = 8 * 1_024 * 1_024,
        missing: Int32? = nil, acceptsChanges: Bool = false
    ) throws -> Data {
        try Task.checkCancellation()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = directory
        process.arguments = [
            "--no-pager", "--literal-pathspecs", "-c", "core.fsmonitor=false", "-c", "diff.suppressBlankEmpty=false"
        ] + arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let read = pipe.fileHandleForReading
        defer {
            try? read.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        var bytes = Data()
        while let chunk = try read.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            guard bytes.count + chunk.count <= limit else { throw GitReviewError.outputTooLarge }
            bytes.append(chunk)
        }
        process.waitUntilExit()
        let code = process.terminationStatus
        if code == missing { return Data() }
        guard process.terminationReason == .exit, code == 0 || (code == 1 && acceptsChanges) else {
            throw GitReviewError.readFailed
        }
        return bytes
    }

    private var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_NO_LAZY_FETCH"] = "1"
        environment["LC_ALL"] = "C"
        return environment
    }
}
