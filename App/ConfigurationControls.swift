import SwiftUI
import SynthProtocol

struct ModeControl: View {
    @Bindable var model: ConversationModel

    var body: some View {
        ConversationDropdown(isPresented: $model.showModePicker) {
            ConversationPopoverLabel(title: modeLabel)
        } content: {
            Text("Mode").font(.headline)
            VStack(spacing: 4) {
                ForEach(model.modes) { mode in
                    let selected = mode.id == model.state?.status?.agent
                    Button {
                        model.showModePicker = false
                        Task { await model.selectMode(mode) }
                    } label: {
                        ConversationPopoverChoice(title: mode.name, selected: selected)
                    }
                }
            }
            .buttonStyle(ConversationPopoverRowStyle())
        }
        .accessibilityLabel("Mode")
        .accessibilityValue(modeLabel)
        .fixedSize()
        .onChange(of: model.sessionID) { model.showModePicker = false }
    }

    private var modeLabel: String {
        model.modes.first { $0.id == model.state?.status?.agent }?.name ?? "Mode"
    }
}

struct ConfigurationControls: View {
    @Bindable var model: ConversationModel

    var body: some View {
        ConversationDropdown(isPresented: $model.showModelPicker, width: 350) {
            ConversationPopoverLabel(title: modelLabel)
        } content: {
            Text("Models").font(.headline)
            ModelBrowser(model: model) { model.showModelPicker = false }
        }
        .accessibilityLabel("Model and reasoning effort")
        .accessibilityValue(modelLabel)
        .onChange(of: model.sessionID) { model.showModelPicker = false }
    }

    private var modelLabel: String {
        guard let status = model.state?.status, !status.model.isEmpty else { return "Model" }
        return status.effort.isEmpty ? status.model : "\(status.model) · \(status.effort.capitalized)"
    }
}

extension ConversationModel {
    func selectMode(_ mode: ACP.Mode) async {
        guard canConfigure, let sessionID else { return }
        do {
            try await configure(in: sessionID) { try await $0.setMode(mode.id, in: $1) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    var canChangeApprovalMode: Bool {
        canReadConfiguration && !isUpdatingConfiguration && state?.status?.approvalMode != nil
    }

    func selectApprovalMode(_ mode: Synth.ApprovalMode, in session: String) async {
        guard canChangeApprovalMode, sessionID == session, state?.status?.approvalMode != mode else { return }
        do {
            try await configure(in: session, whileBusy: true) { try await $0.setApprovalMode(mode, in: $1) }
        } catch where !Task.isCancelled && sessionID == session {
            self.error = error.localizedDescription
        } catch {}
    }
}
