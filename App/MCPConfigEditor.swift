import SwiftUI
import SynthProtocol

struct MCPConfigEditor: View {
    @Environment(\.dismiss) private var dismiss
    let serverName: String
    let initial: JSONValue?
    let saved: (String, JSONValue) throws -> Void
    @State private var name = ""
    @State private var json = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(serverName.isEmpty ? "Add MCP Server" : "Edit MCP Server").font(.title2)
            TextField("Name", text: $name).disabled(!serverName.isEmpty)
            Text("Server Configuration")
                .font(.headline)
            TextEditor(text: $json)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 210)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            Text("Use a command for a local process or a URL for an HTTP server.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 510)
        .onAppear {
            name = serverName
            json = Self.encode(initial ?? .object([:]))
        }
    }

    private func save() {
        error = nil
        let key = serverName.isEmpty ? name.trimmingCharacters(in: .whitespacesAndNewlines) : serverName
        guard !key.isEmpty, key.rangeOfCharacter(from: .newlines) == nil else {
            error = "Enter a server name on one line."
            return
        }
        do {
            guard case .object(let value) = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else {
                throw EditorError.objectRequired
            }
            let command = value["command"].flatMap(Self.string)
            if let url = value["url"].flatMap(Self.string) {
                guard Self.isValidHTTPURL(url) else { throw EditorError.invalidURL }
                guard command == nil else { throw EditorError.ambiguousTransport }
            } else if command?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw EditorError.endpointRequired
            }
            try saved(key, .object(value))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{}"
    }

    private static func string(_ value: JSONValue) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }

    private static func isValidHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value, encodingInvalidCharacters: false),
              let scheme = url.scheme?.lowercased(), let host = url.host else { return false }
        return ["http", "https"].contains(scheme) && !host.isEmpty
    }

    enum EditorError: LocalizedError {
        case objectRequired, endpointRequired, invalidURL, ambiguousTransport

        var errorDescription: String? {
            switch self {
            case .objectRequired: "The server configuration must be a JSON object."
            case .endpointRequired: "Provide a non-empty command or an HTTP(S) URL."
            case .invalidURL: "Enter a valid HTTP(S) URL or remove the URL field to use a command."
            case .ambiguousTransport: "Provide either a command or a URL."
            }
        }
    }
}
