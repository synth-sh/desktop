import Foundation
import SynthProtocol

struct MCPServerDraft {
    enum Transport { case stdio, http }

    struct Value: Identifiable {
        let id = UUID()
        var value = ""
    }

    struct Field: Identifiable {
        let id = UUID()
        var name = ""
        var value = ""
    }

    var transport = Transport.stdio
    var enabled = true
    var command = ""
    var directory = ""
    var arguments: [Value] = []
    var environment: [Field] = []
    var url = ""
    var headers: [Field] = []
    var scopes: [Value] = []
    private var extra: [String: JSONValue] = [:]

    init() {}

    init(_ configuration: JSONValue) throws {
        guard case .object(var fields) = configuration else { throw Failure.objectRequired }
        let url = try Self.removeString("url", from: &fields)
        let command = try Self.removeString("command", from: &fields)
        if url != nil && command != nil { throw Failure.ambiguousTransport }
        transport = url == nil ? .stdio : .http
        self.url = url ?? ""
        self.command = command ?? ""
        directory = try Self.removeString("cwd", from: &fields) ?? ""
        arguments = try Self.removeValues("args", from: &fields)
        environment = try Self.removeFields("env", from: &fields)
        headers = try Self.removeFields("headers", from: &fields)
        scopes = try Self.removeValues("scopes", from: &fields)
        if let state = fields.removeValue(forKey: "enabled") {
            guard case .bool(let enabled) = state else { throw Failure.useJSON("enabled") }
            self.enabled = enabled
        }
        extra = fields
    }

    func configuration() throws -> JSONValue {
        var fields = extra
        fields["enabled"] = .bool(enabled)
        switch transport {
        case .stdio:
            fields["command"] = .string(command)
            if !directory.isEmpty { fields["cwd"] = .string(directory) }
            if !arguments.isEmpty { fields["args"] = .array(arguments.map { .string($0.value) }) }
            if !environment.isEmpty { fields["env"] = .object(try Self.dictionary(environment)) }
        case .http:
            fields["url"] = .string(url)
            if !headers.isEmpty { fields["headers"] = .object(try Self.dictionary(headers)) }
            if !scopes.isEmpty { fields["scopes"] = .array(scopes.map { .string($0.value) }) }
        }
        return .object(fields)
    }

    static func validate(_ configuration: JSONValue) throws {
        guard case .object(let fields) = configuration else { throw Failure.objectRequired }
        let command = fields["command"].flatMap(string)
        if let url = fields["url"].flatMap(string) {
            guard let endpoint = URL(string: url, encodingInvalidCharacters: false),
                  let scheme = endpoint.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = endpoint.host, !host.isEmpty else { throw Failure.invalidURL }
            guard command == nil else { throw Failure.ambiguousTransport }
        } else if command?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw Failure.endpointRequired
        }
    }

    static func decode(_ source: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
    }

    static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{}"
    }

    private static func string(_ value: JSONValue) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }

    private static func removeString(_ key: String, from fields: inout [String: JSONValue]) throws -> String? {
        guard let value = fields.removeValue(forKey: key) else { return nil }
        guard let text = string(value) else { throw Failure.useJSON(key) }
        return text
    }

    private static func removeValues(_ key: String, from fields: inout [String: JSONValue]) throws -> [Value] {
        guard let field = fields.removeValue(forKey: key) else { return [] }
        guard case .array(let values) = field else { throw Failure.useJSON(key) }
        return try values.map {
            guard let value = string($0) else { throw Failure.useJSON(key) }
            return Value(value: value)
        }
    }

    private static func removeFields(_ key: String, from fields: inout [String: JSONValue]) throws -> [Field] {
        guard let field = fields.removeValue(forKey: key) else { return [] }
        guard case .object(let values) = field else { throw Failure.useJSON(key) }
        return try values.keys.sorted().map {
            guard let value = values[$0].flatMap(string) else { throw Failure.useJSON(key) }
            return Field(name: $0, value: value)
        }
    }

    private static func dictionary(_ rows: [Field]) throws -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw Failure.fieldNameRequired }
            guard values[name] == nil else { throw Failure.duplicateField(name) }
            values[name] = .string(row.value)
        }
        return values
    }

    enum Failure: LocalizedError {
        case objectRequired, endpointRequired, invalidURL, ambiguousTransport, fieldNameRequired
        case duplicateField(String), useJSON(String)

        var errorDescription: String? {
            switch self {
            case .objectRequired: "The server configuration must be a JSON object."
            case .endpointRequired: "Provide a non-empty command or an HTTP(S) URL."
            case .invalidURL: "Enter a valid HTTP(S) URL."
            case .ambiguousTransport: "Provide either a command or a URL."
            case .fieldNameRequired: "Enter a name for each header or environment variable."
            case .duplicateField(let name): "The name “\(name)” is used more than once."
            case .useJSON(let key): "Edit “\(key)” in JSON to preserve its current value."
            }
        }
    }
}
