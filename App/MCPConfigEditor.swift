import SwiftUI
import SynthProtocol

struct MCPConfigEditor: View {
    @Environment(\.dismiss) private var dismiss
    let serverName: String
    let initial: JSONValue?
    let saved: (String, JSONValue) throws -> Void
    @State private var name = ""
    @State private var draft = MCPServerDraft()
    @State private var json = ""
    @State private var editingJSON = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(serverName.isEmpty ? "Add MCP Server" : "Edit MCP Server").font(.title2)
                Spacer()
                Button(editingJSON ? "Show Form" : "Edit JSON",
                       systemImage: editingJSON ? "list.bullet.rectangle" : "curlybraces", action: changeEditor)
                    .labelStyle(.iconOnly)
                    .help(editingJSON ? "Show form" : "Edit JSON")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Form {
                Section {
                    TextField("Server Name", text: $name).disabled(!serverName.isEmpty)
                    if !editingJSON {
                        Picker("Transport", selection: $draft.transport) {
                            Text("Standard I/O").tag(MCPServerDraft.Transport.stdio)
                            Text("HTTP").tag(MCPServerDraft.Transport.http)
                        }
                        .pickerStyle(.segmented)
                        Toggle("Enabled", isOn: $draft.enabled)
                    }
                }
                if editingJSON {
                    Section("Server Configuration") {
                        TextEditor(text: $json)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 260)
                            .accessibilityLabel("Server Configuration")
                    }
                } else {
                    transportFields
                }
            }
            .formStyle(.grouped)

            if let error {
                Text(error).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 530, height: 560)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var transportFields: some View {
        switch draft.transport {
        case .stdio:
            Section("Process") {
                TextField("Command", text: $draft.command, prompt: Text("/path/to/server"))
                TextField("Working Directory", text: $draft.directory, prompt: Text("Optional"))
            }
            MCPStringFields(title: "Arguments", item: "Argument", entries: $draft.arguments, reorderable: true)
            MCPKeyValueFields(title: "Environment Variables", item: "Variable", entries: $draft.environment)
        case .http:
            Section("Endpoint") {
                TextField("URL", text: $draft.url, prompt: Text("https://example.com/mcp"))
            }
            MCPKeyValueFields(title: "HTTP Headers", item: "Header", entries: $draft.headers)
            MCPStringFields(title: "OAuth Scopes", item: "Scope", entries: $draft.scopes)
        }
    }

    private func load() {
        name = serverName
        guard let initial else { return }
        json = MCPServerDraft.encode(initial)
        do {
            draft = try MCPServerDraft(initial)
        } catch {
            editingJSON = true
        }
    }

    private func changeEditor() {
        error = nil
        do {
            if editingJSON {
                draft = try MCPServerDraft(MCPServerDraft.decode(json))
            } else {
                json = MCPServerDraft.encode(try draft.configuration())
            }
            editingJSON.toggle()
        } catch {
            self.error = error.localizedDescription
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
            let configuration = try editingJSON ? MCPServerDraft.decode(json) : draft.configuration()
            try MCPServerDraft.validate(configuration)
            try saved(key, configuration)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct MCPStringFields: View {
    let title: String
    let item: String
    @Binding var entries: [MCPServerDraft.Value]
    var reorderable = false

    var body: some View {
        Section(title) {
            ForEach($entries) { $entry in
                HStack {
                    TextField(item, text: $entry.value).labelsHidden().accessibilityLabel(item)
                    if reorderable {
                        Menu("Reorder \(item)", systemImage: "arrow.up.arrow.down") {
                            Button("Move Up") { move(entry.id, by: -1) }
                            Button("Move Down") { move(entry.id, by: 1) }
                        }
                        .menuStyle(.borderlessButton)
                        .labelStyle(.iconOnly)
                        .fixedSize()
                    }
                    Button("Remove \(item)", systemImage: "minus.circle") {
                        entries.removeAll { $0.id == entry.id }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                }
            }
            Button("Add \(item)", systemImage: "plus") { entries.append(.init()) }
                .buttonStyle(.borderless)
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries.indices.contains(index + offset) else { return }
        entries.swapAt(index, index + offset)
    }
}

private struct MCPKeyValueFields: View {
    let title: String
    let item: String
    @Binding var entries: [MCPServerDraft.Field]

    var body: some View {
        Section(title) {
            ForEach($entries) { $entry in
                HStack {
                    TextField("Name", text: $entry.name).accessibilityLabel("\(item) name")
                    TextField("Value", text: $entry.value).accessibilityLabel("\(item) value")
                    Button("Remove \(item)", systemImage: "minus.circle") {
                        entries.removeAll { $0.id == entry.id }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                }
            }
            Button("Add \(item)", systemImage: "plus") { entries.append(.init()) }
                .buttonStyle(.borderless)
        }
    }
}
