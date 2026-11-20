import SwiftUI
import SynthProtocol

struct ApprovalControl: View {
    @Environment(\.synthPalette) private var palette
    let model: ConversationModel
    @State private var isPresented = false
    @State private var confirmationSession: String?

    private var mode: Synth.ApprovalMode? { model.state?.status?.approvalMode }

    var body: some View {
        ConversationDropdown(isPresented: $isPresented, width: 290) {
            ConversationPopoverLabel(title: mode?.title ?? "Approvals")
        } content: {
            Text("Approval mode").font(.headline)
            VStack(spacing: 4) {
                ForEach(Synth.ApprovalMode.allCases, id: \.self) { option in
                    Button { choose(option) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            ConversationPopoverChoice(title: option.title, selected: mode == option)
                            Text(option.detail)
                                .font(.caption)
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .buttonStyle(ConversationPopoverRowStyle())
        }
        .fixedSize()
        .disabled(!model.canChangeApprovalMode)
        .accessibilityLabel("Approval mode")
        .accessibilityValue(mode?.title ?? "Unavailable")
        .help(mode.map { "Approvals: \($0.title)" } ?? "Approvals unavailable")
        .onChange(of: model.sessionID) {
            isPresented = false
            confirmationSession = nil
        }
        .alert("Enable All approvals?", isPresented: confirmsAll, presenting: confirmationSession) { session in
            Button("Cancel", role: .cancel) {}
            Button("Enable All", role: .destructive) {
                Task { await model.selectApprovalMode(.all, in: session) }
            }
        } message: { _ in
            Text("Synth can run commands, change files, and use other available tools in this chat without asking you.")
        }
    }

    private var confirmsAll: Binding<Bool> {
        Binding(get: { confirmationSession != nil }, set: { if !$0 { confirmationSession = nil } })
    }

    private func choose(_ option: Synth.ApprovalMode) {
        isPresented = false
        guard let session = model.sessionID, option != mode else { return }
        if option == .all {
            confirmationSession = session
        } else {
            Task { await model.selectApprovalMode(option, in: session) }
        }
    }
}

private extension Synth.ApprovalMode {
    var title: String { rawValue.capitalized }

    var detail: String {
        switch self {
        case .ask: "Ask you when a tool needs approval."
        case .auto: "Let the model review calls that need approval. Edits inside this project run automatically."
        case .all: "Run all available tool calls without asking."
        }
    }
}
