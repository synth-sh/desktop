import AppKit
import Observation
import SynthClient
import SynthProtocol

@MainActor
@Observable
final class ConversationModel {
    let notifications = ConversationNotifications()
    let browserEnabled = UserDefaults.standard.object(forKey: BrowserPreference.enabled) as? Bool ?? true
    var browserTabs: [String: BrowserTab] = [:]
    var settingsPage = SettingsPage.modelsAndMCP
    var engineSettingsPage = EngineSettingsPage.providers
    var customModelIDs = UserDefaults.standard.dictionary(forKey: "customModelIDs") as? [String: [String]] ?? [:] {
        didSet { UserDefaults.standard.set(customModelIDs, forKey: "customModelIDs") }
    }
    var pendingMCPChanges: Set<String> = []
    var error: String?
    private(set) var project: URL?
    private(set) var sessionID: String?
    private(set) var state: SessionState?
    private(set) var interactions: [Interaction] = []
    var groups = [ConversationGroup(folder: nil)]
    private(set) var pendingSelection: ConversationSelection?
    var activity: [String: SynthClient.Activity] = [:]
    var loadingHistory: Set<String> = []
    var openedSessions: [String: OpenedConversation] = [:]
    var historyBySession: [String: ConversationHistory] = [:]
    @ObservationIgnored var cachedTranscript: ConversationTranscript?
    var drafts: [String: ComposerDraft] = [:]
    var importingAttachments: [String: Int] = [:]
    var failedDrafts: [String: [ComposerDraft]] = [:]
    var showModelPicker = false
    var showModePicker = false
    var failures: [String: String] = [:]
    var didRestore = false
    private(set) var modes: [ACP.Mode] = []
    private(set) var connection: SynthClient.ConnectionState = .disconnected
    var isOpening = false
    private(set) var isShuttingDown = false
    private(set) var isUpdatingConfiguration = false
    private(set) var modelError: String?
    private var fetchingModels: Set<String> = []
    var submissions: [String: Int] = [:]
    var stopping: Set<String> = []
    var client: SynthClient?
    private var observingAttention: Task<Void, Never>?
    private var observing: Task<Void, Never>?

    private var submitting: Int { sessionID.flatMap { submissions[$0] } ?? 0 }
    private var stopRequested: Bool { sessionID.map(stopping.contains) ?? false }
    var anyBusy: Bool { submissions.values.contains { $0 > 0 } || activity.values.contains(where: \.busy) }
    var busy: Bool {
        submitting > 0 || (connection == .connected && state?.failure == nil && state?.status?.isBusy == true)
    }
    var canSwitch: Bool { !isOpening && !isShuttingDown && !isUpdatingConfiguration }
    var canRestartEngine: Bool {
        canSwitch && !anyBusy && importingAttachments.isEmpty && state?.status?.signIn == nil
    }
    var canSend: Bool {
        connection == .connected && sessionID != nil && !isOpening && !isShuttingDown &&
            !isUpdatingConfiguration && state?.failure == nil &&
            state?.status?.providerMissing == false && !stopRequested &&
            !composerDraft.isEmpty && !isImportingAttachments &&
            (state?.status?.vision != false || !composerDraft.hasImages)
    }
    var canStop: Bool {
        connection == .connected && sessionID != nil && busy && !stopRequested && state?.failure == nil
    }
    var canReadConfiguration: Bool {
        sessionID != nil && connection == .connected && !isOpening && !isShuttingDown &&
            state?.status != nil && state?.failure == nil
    }
    var canConfigure: Bool { canReadConfiguration && !busy && !isUpdatingConfiguration }
    var activeProviderID: String? {
        guard let status = state?.status, !status.providerMissing else { return nil }
        return status.providerID
    }
    var canDelete: Bool { canSwitch && connection == .connected && sessionID != nil && !busy }
    var loadingModels: Bool {
        (sessionID.map(fetchingModels.contains) ?? false) || (state?.models?.pending ?? 0) > 0
    }

    func open(in folder: URL? = nil, stored: ACP.SessionInfo? = nil, identifier: String? = nil) async {
        guard canSwitch else { return }
        let target = stored?.id ?? identifier
        pendingSelection = ConversationSelection(folder: folder, sessionID: target)
        isOpening = true
        defer { isOpening = false }
        do {
            let client = try await connectedClient()
            let opened = try await obtainSession(target, in: folder, stored: stored, client: client)
            select(opened)
            await refresh(from: client)
            await loadGroup(folder, refresh: true)
        } catch {
            self.error = error.localizedDescription
            if Self.isMissingSession(error) {
                pendingSelection = ConversationSelection(folder: folder, sessionID: nil)
            }
        }
    }

    private func obtainSession(
        _ identifier: String?, in folder: URL?, stored: ACP.SessionInfo?, client: SynthClient
    ) async throws -> OpenedConversation {
        if let identifier, let opened = openedSessions[identifier],
           let state = await client.sessions[identifier], state.failure == nil {
            return opened
        }
        let cwd = try stored?.cwd ?? identifier.flatMap { openedSessions[$0]?.cwd } ?? workingDirectory(for: folder)
        let setup: ACP.SessionOpened
        let openedID: String
        if let identifier {
            setup = try await client.loadSession(identifier, cwd: cwd)
            openedID = identifier
        } else {
            setup = try await client.newSession(cwd: cwd)
            guard let identifier = setup.sessionId else {
                throw SynthClient.Failure.invalidResponse("missing session ID")
            }
            openedID = identifier
        }
        let modes = setup.modes?.availableModes ?? []
        let opened = OpenedConversation(
            id: openedID, folder: folder, cwd: cwd, modes: modes, checkout: openedSessions[openedID]?.checkout
        )
        openedSessions[openedID] = opened
        if let folder { register(folder) }
        return opened
    }

    private func select(_ opened: OpenedConversation) {
        project = opened.folder
        if sessionID != opened.id { (state, interactions) = (nil, []) }
        sessionID = opened.id
        notifications.select(opened.id)
        pendingSelection = nil
        modes = opened.modes
        error = failures[opened.id]
        modelError = nil
        persist()
    }

    func reconnect() async {
        guard canSwitch else { return }
        guard let client, let sessionID else {
            await open(in: pendingSelection?.folder, identifier: pendingSelection?.sessionID)
            for folder in groups.compactMap(\.folder) {
                await loadGroup(folder, refresh: true)
            }
            return
        }
        isOpening = true
        error = nil
        defer { isOpening = false }
        do {
            let setup: ACP.SessionOpened?
            if await client.connectionState == .connected, let opened = openedSessions[sessionID] {
                setup = try await client.loadSession(sessionID, cwd: opened.cwd)
            } else {
                let failures = try await client.reconnect()
                error = failures[sessionID]
                setup = nil
            }
            if let modes = setup?.modes?.availableModes { self.modes = modes }
            modelError = nil
            await refresh(from: client)
            await refreshHistory()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func connectedClient() async throws -> SynthClient {
        guard !isShuttingDown else { throw SynthClient.Failure.disconnected }
        let engine: SynthClient
        if let client {
            engine = client
        } else {
            engine = try await makeClient()
            client = engine
            await observe(engine)
        }
        if await engine.connectionState != .connected {
            if openedSessions.isEmpty {
                try await engine.connect()
            } else {
                _ = try await engine.reconnect()
            }
        }
        connection = .connected
        return engine
    }

    private func observe(_ client: SynthClient, attention: AsyncStream<SynthClient.AttentionEvent>? = nil) async {
        let events: AsyncStream<SynthClient.AttentionEvent>
        if let attention {
            events = attention
        } else {
            events = await client.attentionEvents()
        }
        observingAttention?.cancel()
        observingAttention = Task { [weak self] in
            for await event in events {
                guard let self, self.client === client, !isShuttingDown else { return }
                let storedGroup = groups.first { $0.sessions.contains { $0.id == event.sessionID } }
                let storedTitle = storedGroup?.sessions.first { $0.id == event.sessionID }?.title
                let title = [activity[event.sessionID]?.title, storedTitle].compactMap { $0 }.first { !$0.isEmpty }
                let folder = openedSessions[event.sessionID]?.folder ?? storedGroup?.folder
                notifications.receive(event, title: title, folder: folder)
            }
        }
        observing = Task { [weak self] in
            for await _ in await client.changes() {
                guard let self else { return }
                await refresh(from: client)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func refresh(from client: SynthClient) async {
        let identifier = sessionID
        let snapshot = await client.viewState(for: identifier)
        guard self.client === client, sessionID == identifier else { return }
        connection = snapshot.connection
        (state, interactions) = (snapshot.session, snapshot.interactions)
        activity = snapshot.activity
        updateWorkspaceCheckout()
        if let identifier, state?.status?.isBusy != true && submitting == 0 {
            stopping.remove(identifier)
        }
    }

    func shutdown() async {
        isShuttingDown = true
        closeBrowsers()
        observingAttention?.cancel()
        observing?.cancel()
        await client?.disconnect()
    }
}

extension ConversationModel {
    private func makeClient() async throws -> SynthClient {
        let executable = Bundle.main.bundleURL.appending(path: "Contents/Helpers/synth")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw SynthClient.Failure.invalidResponse("the bundled Synth engine is missing")
        }
        let environment = await LoginEnvironment.load()
        guard !isShuttingDown else { throw SynthClient.Failure.disconnected }
        return SynthClient(
            executable: executable,
            directory: URL.homeDirectory, environment: environment, browser: browserHandler
        )
    }

    func restartEngine() async {
        guard canRestartEngine, let client, let selected = sessionID else { return }
        let conversations = openedSessions.values.sorted { $0.id < $1.id }
        isOpening = true
        error = nil
        defer { isOpening = false }
        var replacement: SynthClient?
        do {
            let engine = try await makeClient()
            replacement = engine
            let attention = await engine.attentionEvents()
            try await engine.connect()
            let previous = await client.sessions
            guard !isShuttingDown, !previous.values.contains(where: {
                $0.failure == nil && ($0.status?.isBusy == true || $0.status?.signIn != nil)
            }) else {
                throw ConfigurationUnavailable()
            }
            await client.disconnect()
            guard !isShuttingDown else { throw SynthClient.Failure.disconnected }
            observing?.cancel()
            self.client = engine
            await observe(engine, attention: attention)
            await reopenConversations(conversations, selected: selected, states: previous, client: engine)
            await refresh(from: engine)
            await refreshHistory()
        } catch {
            await replacement?.disconnect()
            self.error = error.localizedDescription
        }
    }

    private func reopenConversations(
        _ conversations: [OpenedConversation], selected: String, states: [String: SessionState], client: SynthClient
    ) async {
        var restored = true
        for conversation in conversations {
            guard !isShuttingDown else { return }
            do {
                let opened = try await reopen(conversation, state: states[conversation.id], client: client)
                if conversation.id == selected { select(opened) }
            } catch {
                restored = false
                if conversation.id == selected { self.error = error.localizedDescription }
            }
        }
        if restored {
            pendingMCPChanges.removeAll()
        } else if error == nil {
            error = "Some conversations could not be reopened. Select a conversation to try again."
        }
    }

    private func reopen(
        _ previous: OpenedConversation, state: SessionState?, client: SynthClient
    ) async throws -> OpenedConversation {
        do {
            return try await obtainSession(previous.id, in: previous.folder, stored: nil, client: client)
        } catch where state?.messages.isEmpty == true && state?.dropped == 0 && Self.isMissingSession(error) {
            let opened = try await obtainSession(nil, in: previous.folder, stored: nil, client: client)
            openedSessions.removeValue(forKey: previous.id)
            drafts[opened.id] = drafts.removeValue(forKey: previous.id)
            failedDrafts[opened.id] = failedDrafts.removeValue(forKey: previous.id)
            return opened
        }
    }

    func clearSelection() {
        project = nil
        sessionID = nil
        notifications.select(nil)
        pendingSelection = nil
        modes = []
        error = nil
        persist()
    }

    func stop() async {
        guard canStop, let client, let sessionID else { return }
        stopping.insert(sessionID)
        do {
            try await client.cancelTurn(in: sessionID)
        } catch {
            stopping.remove(sessionID)
            if self.sessionID == sessionID { self.error = error.localizedDescription }
        }
    }
}

private struct ConfigurationUnavailable: LocalizedError {
    var errorDescription: String? { "This conversation is not ready for changes." }
}

extension ConversationModel {
    func fetchModels() async {
        guard canReadConfiguration, let client, let sessionID, fetchingModels.insert(sessionID).inserted else { return }
        modelError = nil
        defer { fetchingModels.remove(sessionID) }
        do {
            try await client.fetchModels(in: sessionID)
        } catch where !Task.isCancelled && self.sessionID == sessionID && self.client === client {
            modelError = error.localizedDescription
        } catch {}
    }

    func configure(
        in session: String, whileBusy: Bool = false, _ operation: (SynthClient, String) async throws -> Void
    ) async throws {
        guard canReadConfiguration, !isUpdatingConfiguration, whileBusy || !busy,
              sessionID == session, let client else { throw ConfigurationUnavailable() }
        isUpdatingConfiguration = true
        defer { isUpdatingConfiguration = false }
        do {
            try await operation(client, session)
        } catch {
            await refresh(from: client)
            throw error
        }
        await refresh(from: client)
    }

    func decide(_ request: RequestID, option: String) async {
        await respond { try await $0.decide(request, optionID: option) }
    }

    func answer(_ request: RequestID, fields: [String: String]) async {
        await respond { try await $0.answer(request, fields: fields) }
    }

    func decline(_ request: RequestID) async {
        await respond { try await $0.declineQuestion(request) }
    }

    private func respond(_ operation: (SynthClient) async throws -> Void) async {
        guard let client else { return }
        do {
            try await operation(client)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
