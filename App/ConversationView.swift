import SwiftUI
import SynthClient
import SynthProtocol

struct ConversationView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.synthPalette) private var palette
    @Bindable var model: ConversationModel
    @State private var renameTarget: String?
    @State private var deleteTarget: String?
    @State private var titleActionsPresented = false
    @State private var renameText = ""
    @State private var scrollAnchors: [String: TranscriptAnchor] = [:]
    @State private var composerFocused = false
    @State private var composerController = ComposerController()
    @State private var workspaceHeight: CGFloat = 700
    @State private var showsGitChanges = false
    @State private var windowWidth: CGFloat = 900
    @AppStorage("gitReviewPaneWidth") private var gitReviewWidth = 0.0

    var body: some View {
        NavigationSplitView {
            ProjectSidebar(model: model)
        } detail: {
            workspace
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .overlay(alignment: .topTrailing) {
            if let alert = model.notifications.toast {
                ConversationToast(alert: alert) {
                    model.notifications.open(alert.sessionID, folder: alert.folder)
                }
                .padding(14)
            }
        }
        .background {
            ConversationWindowReader { window in
                model.notifications.window = window
                let open = openWindow
                model.notifications.showWindow = { open(id: "conversation") }
                model.notifications.focusChanged()
            }
            .frame(width: 0, height: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.notifications.focusChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            model.notifications.focusChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.notifications.focusChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.notifications.focusChanged()
        }
        .task { await model.restore() }
    }

    private var detail: some View {
        Group {
            if model.sessionID != nil {
                conversation
            } else if model.isOpening || model.error != nil {
                opening
            } else {
                welcome
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .foregroundStyle(palette.foreground)
        .alert("Rename Conversation", isPresented: isPresenting($renameTarget)) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let identifier = renameTarget else { return }
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await model.rename(name, in: identifier) }
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Conversation?", isPresented: isPresenting($deleteTarget)) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let identifier = deleteTarget else { return }
                Task {
                    if await model.deleteConversation(identifier) { scrollAnchors.removeValue(forKey: identifier) }
                }
            }
        } message: {
            Text("This permanently removes the conversation and its saved history.")
        }
        .onChange(of: model.sessionID) {
            titleActionsPresented = false
            if model.sessionID != nil { composerFocused = true }
        }
    }

    private var conversationTitle: String {
        guard model.sessionID != nil else { return "Synth" }
        return model.state?.status?.title.nonEmpty ?? "Untitled conversation"
    }

    private func isPresenting(_ target: Binding<String?>) -> Binding<Bool> {
        Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })
    }

    private func titleMenu(for identifier: String) -> some View {
        Button { titleActionsPresented.toggle() } label: {
            ConversationPopoverLabel(title: conversationTitle)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .popover(isPresented: $titleActionsPresented, arrowEdge: .bottom) {
            ConversationPopover {
                VStack(spacing: 4) {
                    Button("Rename…", systemImage: "pencil") {
                        titleActionsPresented = false
                        renameText = model.state?.status?.title ?? ""
                        renameTarget = identifier
                    }
                    .disabled(!model.canConfigure)
                    Button("Delete…", systemImage: "trash", role: .destructive) {
                        titleActionsPresented = false
                        deleteTarget = identifier
                    }
                    .disabled(!model.canDelete)
                }
                .buttonStyle(ConversationPopoverRowStyle())
            }
        }
        .accessibilityHint("Conversation actions")
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label("Start a conversation", systemImage: "bubble.left.and.bubble.right")
        } actions: {
            Button("New Conversation") { Task { await model.open() } }
                .buttonStyle(SynthProminentButtonStyle())
            Button("Open Project…", action: model.chooseProject)
        }
    }

    private var opening: some View {
        Group {
            if model.isOpening {
                ProgressView("Connecting to Synth…")
            } else {
                ContentUnavailableView {
                    Label("Couldn't open a conversation", systemImage: "exclamationmark.circle")
                } description: {
                    if let error = model.error { Text(error).textSelection(.enabled) }
                } actions: {
                    Button("Retry") { Task { await model.reconnect() } }
                        .buttonStyle(SynthProminentButtonStyle())
                }
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            banners
            if let identifier = model.sessionID {
                let transcript = model.transcript
                if transcript.firstSequence == nil, model.state?.stream == nil, model.interactions.isEmpty {
                    emptyConversation
                } else {
                    TranscriptView(
                        sessionID: identifier,
                        transcript: transcript,
                        stream: model.state?.stream,
                        status: model.state?.status,
                        notices: model.state?.notices ?? [],
                        interactions: model.interactions,
                        model: model,
                        anchor: Binding(
                            get: { scrollAnchors[identifier] },
                            set: { scrollAnchors[identifier] = $0 }
                        )
                    )
                    .id(identifier)
                }
            }
            composer
            if let status = model.state?.status, !status.root.isEmpty {
                CheckoutContext(root: status.root, branch: status.branch)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { workspaceHeight = $0 }
    }

    private var emptyConversation: some View {
        let prompt = model.project == nil ? "Ask a question or describe a task." :
            "Ask about your project or describe a change."
        return ContentUnavailableView(
            "Start a conversation",
            systemImage: "bubble.left.and.text.bubble.right",
            description: Text(prompt)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notices = model.state?.notices, !notices.isEmpty {
                ScrollView { TranscriptNotices(notices: notices) }
                    .frame(maxWidth: 730, maxHeight: 54)
                    .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if let failure = connectionFailure {
            banner(failure, actionTitle: "Reconnect") { await model.reconnect() }
        } else if model.state?.status?.providerMissing == true {
            providerBanner
        } else if let error = model.error {
            banner(error, actionTitle: "Dismiss") { model.error = nil }
        }
    }

    private var providerBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(palette.accent)
            Text(model.error ?? "Connect a provider to start chatting.").textSelection(.enabled)
            Spacer()
            Button("Retry") { Task { await model.restartEngine() } }
                .disabled(!model.canRestartEngine)
            Button("Manage Providers…") {
                model.settingsPage = .modelsAndMCP
                model.engineSettingsPage = .providers
                openSettings()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(palette.alternateSurface)
    }

    private var connectionFailure: String? {
        if let failure = model.state?.failure { return failure }
        if case .failed(let message) = model.connection { return message }
        return nil
    }

    private func banner(
        _ text: String, actionTitle: String, action: @escaping @MainActor () async -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(palette.accent)
            Text(text).textSelection(.enabled)
            Spacer()
            Button(actionTitle) { Task { await action() } }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(palette.alternateSurface)
    }

}

extension ConversationView {
    private var composer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if composerFocused && composerController.showsCompletions {
                ComposerCompletions(model: model, controller: composerController)
            }
            if !model.composerDraft.attachments.isEmpty {
                ComposerAttachmentStrip(model: model, controller: composerController)
            }
            composerBox
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var composerBox: some View {
        VStack(alignment: .leading, spacing: 9) {
            composerInput
            ComposerControls(model: model)
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(composerFocused ? palette.accent : palette.border)
                .allowsHitTesting(false)
        }
    }

    private var composerInput: some View {
        RichComposer(
            model: model, focused: $composerFocused, controller: composerController,
            maximumHeight: min(300, max(170, workspaceHeight * 0.40))
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension ConversationView {
    private var workspace: some View {
        ResizableTrailingPane(
            savedWidth: $gitReviewWidth, isPresented: showsGitChanges && checkoutDirectory != nil,
            defaultWidth: windowWidth * 0.4, minimumWidth: 285, minimumMainWidth: 245, dividerLabel: "Git pane width"
        ) {
            detail
        } pane: {
            if let checkoutDirectory {
                GitReviewPane(directory: checkoutDirectory, turnCompletion: model.state?.status?.finished)
                    .id(checkoutDirectory)
            }
        }
        .navigationTitle(conversationTitle)
        .toolbar(removing: model.sessionID == nil ? nil : .title)
        .toolbar { workspaceToolbar }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    private var checkoutDirectory: URL? {
        guard model.sessionID != nil else { return nil }
        if let status = model.state?.status, !status.root.isEmpty, model.project != nil || !status.branch.isEmpty {
            return URL(fileURLWithPath: status.root, isDirectory: true).standardizedFileURL
        }
        return model.project
    }

    @ToolbarContentBuilder
    var workspaceToolbar: some ToolbarContent {
        if let identifier = model.sessionID {
            ToolbarItem(placement: .navigation) { titleMenu(for: identifier) }
        }
        if checkoutDirectory != nil {
            ToolbarSpacer(.flexible, placement: .automatic)
            ToolbarItem(placement: .automatic) {
                Button(gitChangesAction, systemImage: "rectangle.split.2x1") {
                    showsGitChanges.toggle()
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel(gitChangesAction)
                .help(gitChangesAction)
            }
        }
    }

    var gitChangesAction: String { showsGitChanges ? "Hide Git Changes" : "Show Git Changes" }
}
