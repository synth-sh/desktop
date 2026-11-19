import SwiftUI

enum EngineSettingsPage: Hashable { case providers, mcp }

struct EngineSettings: View {
    @Bindable var model: ConversationModel

    var body: some View {
        if model.isOpening {
            ProgressView("Opening conversation…")
        } else if model.canReadConfiguration {
            VStack(spacing: 0) {
                HStack {
                    Picker("Manage", selection: $model.engineSettingsPage) {
                        Text("Providers").tag(EngineSettingsPage.providers)
                        Text("MCP Servers").tag(EngineSettingsPage.mcp)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()

                }
                .padding(12)
                if model.busy {
                    Text("Finish the current turn to make changes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
                Divider()
                Group {
                    switch model.engineSettingsPage {
                    case .providers: ProviderSettings(model: model)
                    case .mcp: MCPSettings(model: model)
                    }
                }
                .id(model.sessionID)
            }
        } else {
            ContentUnavailableView {
                Label("No connected conversation", systemImage: "link")
            } description: {
                Text(model.state?.failure ?? model.error ?? "Open a conversation to manage providers and MCP servers.")
            } actions: {
                if model.sessionID == nil {
                    Button("New Conversation") { Task { await model.open() } }
                        .disabled(!model.canSwitch)
                } else {
                    Button("Reconnect") { Task { await model.reconnect() } }
                        .disabled(!model.canSwitch)
                }
            }
        }
    }
}
