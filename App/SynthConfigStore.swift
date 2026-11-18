import Foundation
import SynthProtocol

struct SynthConfigStore: Sendable {
    let file: URL

    static func loadEnvironment() async -> Self {
        let environment = await LoginEnvironment.load()
        let base = environment["XDG_CONFIG_HOME"] ?? environment["HOME"].map { "\($0)/.config" }
        let directory = URL(fileURLWithPath: base ?? FileManager.default.homeDirectoryForCurrentUser.path + "/.config")
        return Self(file: directory.appending(path: "synth/config.json"))
    }

    func object() throws -> [String: JSONValue] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        guard case .object(let object) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw Failure.invalidRoot
        }
        return object
    }

    // Preserves every unrelated config key; callers only own the value they update.
    func update(_ key: String, transform: (JSONValue?) throws -> JSONValue) throws {
        var config = try object()
        config[key] = try transform(config[key])
        try write(config)
    }

    func mcpServers() throws -> [String: JSONValue] {
        guard case .object(let mcp) = try object()["mcp"],
              case .object(let servers) = mcp["servers"] else { return [:] }
        return servers
    }

    func updateMCPServers(_ update: (inout [String: JSONValue]) throws -> Void) throws {
        try self.update("mcp") { value in
            var servers: [String: JSONValue] = [:]
            var mcp: [String: JSONValue] = [:]
            if case .object(let existing)? = value {
                mcp = existing
                if case .object(let saved)? = existing["servers"] { servers = saved }
            }
            try update(&servers)
            mcp["servers"] = .object(servers)
            return .object(mcp)
        }
    }

    private func write(_ object: [String: JSONValue]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(JSONValue.object(object))
        data.append(0x0A)
        let temporary = file.appendingPathExtension("tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temporary, options: .atomic)
            if manager.fileExists(atPath: file.path) {
                try manager.replaceItemAt(file, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: file)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    enum Failure: LocalizedError {
        case invalidRoot

        var errorDescription: String? { "Synth config.json must contain a JSON object." }
    }
}
