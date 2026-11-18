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
            Text("Enter a server object with a command or URL. Other Synth config remains unchanged.")
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
            json = Self.encode(initial ?? .object(["url": .string("https://")] ))
        }
    }

    private func save() {
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .newlines) == nil else {
            error = "Enter a server name on one line."
            return
        }
        do {
            guard case .object(let value) = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else {
                throw EditorError.objectRequired
            }
            let command = value["command"].flatMap(Self.string)
            let url = value["url"].flatMap(Self.validURL)
            guard command?.isEmpty == false || url != nil else {
                throw EditorError.endpointRequired
            }
            try saved(trimmed, .object(value))
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

    private static func validURL(_ value: JSONValue) -> URL? {
        guard let string = string(value), let url = URL(string: string),
              ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil else { return nil }
        return url
    }

    enum EditorError: LocalizedError {
        case objectRequired, endpointRequired

        var errorDescription: String? {
            switch self {
            case .objectRequired: "The server configuration must be a JSON object."
            case .endpointRequired: "Provide a non-empty command or an HTTP(S) URL."
            }
        }
    }
}
