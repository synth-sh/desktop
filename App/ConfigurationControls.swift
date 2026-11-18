import SwiftUI

struct ModeControl: View {
    @Bindable var model: ConversationModel

    var body: some View {
        Button { model.showModePicker.toggle() } label: {
            ConversationPopoverLabel(title: modeLabel)
        }
        .accessibilityLabel("Mode")
        .accessibilityValue(modeLabel)
        .fixedSize()
        .popover(isPresented: $model.showModePicker, arrowEdge: .top) {
            ConversationPopover {
                Text("Mode").font(.headline)
                VStack(spacing: 4) {
                    ForEach(model.modes) { mode in
                        let selected = mode.id == model.state?.status?.agent
                        Button {
                            model.showModePicker = false
                            Task { await model.selectMode(mode) }
                        } label: {
                            HStack {
                                Text(mode.name)
                                Spacer()
                                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }
                        }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .buttonStyle(ConversationPopoverRowStyle())
            }
        }
        .onChange(of: model.sessionID) { model.showModePicker = false }
    }

    private var modeLabel: String {
        model.modes.first { $0.id == model.state?.status?.agent }?.name ?? "Mode"
    }
}

struct ConfigurationControls: View {
    @Bindable var model: ConversationModel

    var body: some View {
        Button { model.showModelPicker.toggle() } label: {
            ConversationPopoverLabel(title: modelLabel)
        }
        .accessibilityLabel("Model and reasoning effort")
        .accessibilityValue(modelLabel)
        .popover(isPresented: $model.showModelPicker, arrowEdge: .top) {
            ConversationPopover(width: 350) {
                Text("Models").font(.headline)
                ModelBrowser(model: model) { model.showModelPicker = false }
            }
        }
        .onChange(of: model.sessionID) { model.showModelPicker = false }
    }

    private var modelLabel: String {
        guard let status = model.state?.status, !status.model.isEmpty else { return "Model" }
        return status.effort.isEmpty ? status.model : "\(status.model) · \(status.effort.capitalized)"
    }
}
