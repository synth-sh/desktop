import SwiftUI
import SynthProtocol

struct ModelBrowser: View {
    @Environment(\.synthPalette) private var palette
    let model: ConversationModel
    var providerID: String?
    var readOnly = false
    var onApply: () -> Void = {}

    @State private var query = ""
    @State private var highlight: String?
    @State private var effort: String?
    @State private var applyError: String?

    var body: some View {
        let groups = groups
        let choices = groups.flatMap(\.choices)
        let selected = choices.first { $0.id == highlight } ??
            (search.isEmpty ? choices.first(where: isCurrent) : nil) ?? choices.first

        VStack(alignment: .leading, spacing: 9) {
            HStack {
                ModelSearchField(
                    text: $query, placeholder: readOnly ? "Search models" : searchPlaceholder,
                    autofocus: !readOnly && providerID == nil,
                    move: { move($0, in: choices, from: selected) }, submit: {
                        if !readOnly { apply(selected) }
                    }
                )
                .frame(height: 22)
                Button("Refresh Models", systemImage: "arrow.clockwise") {
                    Task { await model.fetchModels() }
                }
                .labelStyle(.iconOnly)
                .disabled(model.loadingModels)
                .help("Refresh models")
            }
            if model.loadingModels {
                ProgressView("Finding models…").controlSize(.small)
            }
            if let error = applyError ?? model.modelError {
                Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            if !choices.isEmpty {
                results(groups, selected: selected)
            } else if !model.loadingModels && model.modelError == nil {
                Text(search.isEmpty ? "No models available for this provider selection." : "No matching models.")
                    .foregroundStyle(.secondary)
            }
            if !readOnly, let selected {
                Divider()
                selectionControls(selected)
            }
        }
        .onChange(of: query) {
            highlight = nil
            applyError = nil
        }
        .onChange(of: selected?.id) { effort = nil }
        .onAppear {
            if !model.loadingModels { Task { await model.fetchModels() } }
        }
    }

    private var search: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canApply: Bool { model.canConfigure && model.state?.status?.signIn == nil }
    private var manualProvider: String? {
        guard let active = model.activeProviderID, providerID == nil || providerID == active,
              ProviderKind(rawValue: active)?.allowsManualModel == true else { return nil }
        return active
    }

    private var searchPlaceholder: String {
        if manualProvider != nil {
            return providerID == nil ? "Search models or providers, or enter an ID" : "Search or enter model ID"
        }
        return providerID == nil ? "Search models or providers" : "Search models"
    }

    private var groups: [ModelGroup] {
        let catalog = model.state?.models
        var offers = catalog?.offered ?? []
        if let status = model.state?.status, model.activeProviderID != nil, !status.model.isEmpty,
           !offers.contains(where: { $0.providerID == status.providerID && $0.name == status.model }) {
            offers.insert(.init(name: status.model, provider: status.provider, providerID: status.providerID), at: 0)
        }
        var seen: Set<String> = []
        let matching = offers.filter { offer in
            (providerID == nil || offer.providerID == providerID) && seen.insert(offer.id).inserted &&
                (search.isEmpty || offer.name.localizedCaseInsensitiveContains(search) ||
                    offer.provider.localizedCaseInsensitiveContains(search) ||
                    offer.providerID.localizedCaseInsensitiveContains(search))
        }
        let byName = Dictionary(grouping: matching, by: \.name)
        let recent = readOnly ? [] : (catalog?.recent ?? []).flatMap { byName[$0] ?? [] }
        let recentIDs = Set(recent.map(\.id))
        let byProvider = Dictionary(grouping: matching.filter { !recentIDs.contains($0.id) }, by: \.providerID)
        var groups = byProvider.values.compactMap { offers -> ModelGroup? in
            guard let first = offers.first else { return nil }
            return .init(id: first.providerID, title: first.provider, choices: offers.map { ModelChoice(model: $0) })
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if !recent.isEmpty {
            let choices = recent.map { ModelChoice(model: $0) }
            groups.insert(.init(id: "recent", title: "Recent in This Project", choices: choices), at: 0)
        }
        if !readOnly, !search.isEmpty, let manualProvider,
           !matching.contains(where: { $0.providerID == manualProvider && $0.name == search }) {
            let title = ProviderKind(rawValue: manualProvider)?.title ?? manualProvider
            let option = Synth.Model(name: search, provider: title, providerID: manualProvider)
            groups.append(.init(id: "manual", title: "Manual Entry", choices: [.init(model: option, manual: true)]))
        }
        return groups
    }

    private func results(_ groups: [ModelGroup], selected: ModelChoice?) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(groups) { group in
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.choices) { option in
                            row(option, highlighted: option.id == selected?.id)
                                .id(option.id)
                        }
                    }
                }
            }
            .frame(minHeight: 55, maxHeight: providerID == nil ? 270 : .infinity)
            .onChange(of: selected?.id, initial: true) {
                if let selected { reader.scrollTo(selected.id) }
            }
        }
    }

    private func row(_ option: ModelChoice, highlighted: Bool) -> some View {
        Button {
            guard !readOnly else { return }
            highlight = option.id
            applyError = nil
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.manual ? "Use ‘\(option.model.name)’" : option.model.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if providerID == nil {
                        Text(option.model.provider).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isCurrent(option) {
                    Image(systemName: "checkmark")
                        .accessibilityLabel("Current model")
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(.rect)
            .background(highlighted ? highlightColor : Color.clear, in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
        .disabled(readOnly || model.isUpdatingConfiguration)
    }

    private var highlightColor: Color {
        providerID == nil ? palette.alternateSurface : Color.accentColor.opacity(0.16)
    }

    private func selectionControls(_ selected: ModelChoice) -> some View {
        let levels = isCurrent(selected) ? (model.state?.status?.efforts ?? []) : selected.model.efforts
        let remembered = isCurrent(selected) ? (model.state?.status?.effort ?? "") : selected.model.effort
        let current = isCurrent(selected)
        let defaultEffort = levels.contains(remembered) ? remembered : levels.first ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            if !levels.isEmpty {
                ReasoningEffortSlider(levels: levels, selection: Binding(
                    get: { effort.flatMap { levels.contains($0) ? $0 : nil } ?? defaultEffort },
                    set: { effort = $0 == defaultEffort ? nil : $0; applyError = nil }
                )) {
                    if current, effort != nil { apply(selected, dismiss: false) }
                }
                .id(selected.id)
            }
            if !current {
                Button("Use Model") { apply(selected) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .disabled(!canApply)
    }

    private func isCurrent(_ option: ModelChoice) -> Bool {
        model.activeProviderID == option.model.providerID && model.state?.status?.model == option.model.name
    }

    private func move(_ offset: Int, in choices: [ModelChoice], from selected: ModelChoice?) {
        guard !model.isUpdatingConfiguration,
              let index = choices.firstIndex(where: { $0.id == selected?.id }) else { return }
        highlight = choices[min(max(index + offset, 0), choices.count - 1)].id
        applyError = nil
    }

    private func apply(_ selected: ModelChoice?, dismiss: Bool = true) {
        guard canApply, let selected, let session = model.sessionID else { return }
        let current = isCurrent(selected)
        let levels = current ? (model.state?.status?.efforts ?? []) : selected.model.efforts
        let level = effort.flatMap { levels.contains($0) ? $0 : nil }
        if current, level == nil {
            if dismiss { onApply() }
            return
        }
        applyError = nil
        Task {
            do {
                try await model.configure(in: session) { client, session in
                    if current, let level {
                        try await client.setEffort(level, in: session)
                    } else {
                        try await client.setModel(selected.model, effort: level, in: session)
                    }
                }
                effort = nil
                if dismiss { onApply() }
            } catch {
                if current { effort = nil }
                applyError = error.localizedDescription
            }
        }
    }
}

private struct ModelChoice: Identifiable {
    let model: Synth.Model
    var manual = false
    var id: String { model.id }
}

private struct ModelGroup: Identifiable {
    let id: String
    let title: String
    let choices: [ModelChoice]
}
