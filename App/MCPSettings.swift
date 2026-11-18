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
                }
                if let toggleError { Text(toggleError).foregroundStyle(.red).textSelection(.enabled) }
            }
            Section {
                Text("Configuration changes apply to new conversations. Connection toggles apply immediately.")
                if let path = store?.file.path {
                    LabeledContent("Config file", value: path).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .task { await load() }
        .sheet(isPresented: Binding(get: { editorName != nil }, set: { if !$0 { editorName = nil } })) {
            MCPConfigEditor(
                serverName: editorName ?? "", initial: editorName.flatMap { configured[$0] }
            ) { name, value in
                try store?.updateMCPServers { $0[name] = value }
                configured[name] = value
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let status {
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
            if let status {
                Text(statusLabel(status.state)).font(.caption).foregroundStyle(.secondary)
                if let command = signInCommand(status) {
                    Text("Not signed in. Run this in Terminal, then start a new conversation:")
                        .font(.caption)
                    Text(verbatim: command).font(.caption.monospaced()).textSelection(.enabled)
                } else if !status.reason.isEmpty {
                    Text(status.reason).font(.caption).textSelection(.enabled)
                }
            } else {
                Text("Starts in a new conversation.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statusLabel(_ state: Synth.MCPServer.State) -> String {
        switch state {
        case .off: "Disabled"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .failed: "Connection failed"
        }
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
        guard let deleting else { return }
        do {
            try store?.updateMCPServers { $0.removeValue(forKey: deleting) }
            configured.removeValue(forKey: deleting)
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
