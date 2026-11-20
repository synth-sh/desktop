import SwiftUI

struct ComposerControls: View {
    @Environment(\.synthPalette) private var palette
    let model: ConversationModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                sessionControls
                Spacer(minLength: 0)
                promptControls
            }
            VStack(alignment: .leading, spacing: 6) {
                sessionControls
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    promptControls
                }
            }
        }
    }

    private var sessionControls: some View {
        HStack(spacing: 12) {
            connectionLabel
            ModeControl(model: model)
                .disabled(!model.canConfigure)
            ApprovalControl(model: model)
        }
    }

    private var promptControls: some View {
        HStack(spacing: 12) {
            ConfigurationControls(model: model)
                .disabled(!model.canReadConfiguration)
            if model.busy {
                Button("Stop", systemImage: "stop.fill") { Task { await model.stop() } }
                    .disabled(!model.canStop)
            }
            Button {
                Task { await model.send() }
            } label: {
                Label(model.busy ? "Steer" : "Send", systemImage: "arrow.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(SynthProminentButtonStyle())
            .disabled(!model.canSend)
            .help(model.busy ? "Steer (↩)" : "Send (↩)")
        }
    }

    @ViewBuilder
    private var connectionLabel: some View {
        if model.connection == .connected && !model.isOpening {
            Circle().fill(palette.success)
                .frame(width: 8, height: 8).padding(4)
                .accessibilityLabel("Connected")
                .help(model.busy ? "Connected · \(connectionText)" : "Connected")
        } else {
            Label(connectionText, systemImage: "circle.dashed")
                .lineLimit(1).font(.caption)
                .foregroundStyle(palette.muted)
        }
    }

    private var connectionText: String {
        if model.isOpening { return "Opening conversation…" }
        if model.busy, let label = model.state?.status?.label, !label.isEmpty { return label }
        switch model.connection {
        case .connected: return model.busy ? "Working…" : "Connected"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .failed, .disconnected: return "Disconnected"
        }
    }
}
