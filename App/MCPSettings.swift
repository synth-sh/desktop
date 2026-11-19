import SwiftUI
import SynthProtocol

struct MCPSettings: View {
    let model: ConversationModel
    @State private var configured: [String: JSONValue] = [:]
    @State private var store: SynthConfigStore?
    @State private var toggleError: String?
    @State private var editorName: String?
    @State private var deleting: String?

    var body: some View {
        Form {
            Section("Configured Servers") {
                if configured.isEmpty {
                    Text("No MCP servers configured.").foregroundStyle(.secondary)
                } else {
                    ForEach(configured.keys.sorted(), id: \.self) { name in
                        configuredRow(name)
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Server…") { editorName = "" }
                        .disabled(store == nil)
                }
                if let toggleError { Text(toggleError).foregroundStyle(.red).textSelection(.enabled) }
            }
            Section {
                LabeledContent {
                    Button("Restart Engine") { Task { await model.restartEngine() } }
                        .disabled(!model.canRestartEngine)
                } label: {
                    Text(model.pendingMCPChanges.isEmpty
                         ? "Restart the engine to reload configuration for open conversations."
                         : "MCP configuration changed. Restart the engine to update open conversations.")
                }
                if let path = store?.file.path {
                    LabeledContent("Config file", value: path).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .task { await load() }
        .sheet(isPresented: Binding(get: { editorName != nil }, set: { if !$0 { editorName = nil } })) {
            if let store, let editorName {
                MCPConfigEditor(serverName: editorName, initial: configured[editorName]) { name, value in
                    try store.saveMCPServer(name, configuration: value, isNew: editorName.isEmpty)
                    if configured[name] != value { model.pendingMCPChanges.insert(name) }
                    configured[name] = value
                }
            }
        }
        .confirmationDialog("Delete \(deleting ?? "server")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button("Delete Server", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func configuredRow(_ name: String) -> some View {
        let status = model.state?.status?.mcp?.first { $0.name == name }
        let pending = model.pendingMCPChanges.contains(name)
        let disabledInConfig = isDisabledInConfig(configured[name])
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let status, !pending, !disabledInConfig {
                    Toggle(isOn: Binding(get: { status.isEnabled }, set: { toggle(status, enabled: $0) })) {
                        Text(name)
                    }
                    .toggleStyle(.switch)
                    .disabled(!model.canConfigure || status.state == .connecting)
                } else {
                    Label(name, systemImage: "server.rack")
                }
                Spacer()
                Button("Edit") { editorName = name }.buttonStyle(.borderless)
                Button("Delete", role: .destructive) { deleting = name }.buttonStyle(.borderless)
            }
            if pending {
                Text("Restart the engine to apply this change.").font(.caption).foregroundStyle(.secondary)
            } else if disabledInConfig {
                Text("Disabled in configuration. Edit the server to enable it.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                statusIndicator(status?.state)
            }
            if let status {
                if let command = signInCommand(status) {
                    Text("Not signed in. Run this in Terminal, then start a new conversation:")
                        .font(.caption)
                    Text(verbatim: command).font(.caption.monospaced()).textSelection(.enabled)
                } else if !status.reason.isEmpty {
                    Text(status.reason).font(.caption).textSelection(.enabled)
                }
            }
        }
    }

    private func isDisabledInConfig(_ configuration: JSONValue?) -> Bool {
        guard case .object(let fields) = configuration else { return false }
        return fields["enabled"] == .bool(false)
    }

    private func statusIndicator(_ state: Synth.MCPServer.State?) -> some View {
        let title: String
        let color: Color
        switch state {
        case .off: (title, color) = ("Disabled", .secondary)
        case .connecting: (title, color) = ("Connecting…", .orange)
        case .connected: (title, color) = ("Connected", .green)
        case .failed: (title, color) = ("Connection failed", .red)
        case nil: (title, color) = ("Not loaded in this conversation.", .secondary)
        }
        return Label {
            Text(title).foregroundStyle(.secondary)
        } icon: {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
        }
        .font(.caption)
    }

    private func signInCommand(_ server: Synth.MCPServer) -> String? {
        guard server.reason.contains("synth mcp auth <name>"),
              server.name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return "synth mcp auth '\(server.name.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func load() async {
        do {
            let store = await SynthConfigStore.loadEnvironment()
            self.store = store
            configured = try store.mcpServers()
            toggleError = nil
        } catch {
            toggleError = error.localizedDescription
        }
    }

    private func remove() {
        guard let deleting, let store else { return }
        do {
            try store.updateMCPServers { $0.removeValue(forKey: deleting) }
            configured.removeValue(forKey: deleting)
            model.pendingMCPChanges.insert(deleting)
            self.deleting = nil
            toggleError = nil
        } catch {
            toggleError = error.localizedDescription
        }
    }

    private func toggle(_ server: Synth.MCPServer, enabled: Bool) {
        guard let session = model.sessionID, enabled != server.isEnabled else { return }
        toggleError = nil
        Task {
            do {
                try await model.configure(in: session) { try await $0.toggleMCP(server.id, in: $1) }
            } catch {
                toggleError = error.localizedDescription
            }
        }
    }
}
