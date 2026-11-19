import SwiftUI
import SynthProtocol

struct ProviderSettings: View {
    let model: ConversationModel
    @State private var providers: [Synth.Provider]?
    @State private var selection: String?
    @State private var loadError: String?
    @State private var signInError: String?

    var body: some View {
        let signIn = model.state?.status?.signIn
        VStack(spacing: 0) {
            if let signIn {
                signInControls(signIn)
                Divider()
            }
            if let providers {
                HStack(spacing: 0) {
                    List(providers, selection: $selection) { provider in
                        providerRow(provider).tag(provider.id)
                    }
                    .listStyle(.sidebar)
                    .frame(width: 178)
                    .disabled(model.isUpdatingConfiguration)
                    Divider()
                    if let provider = providers.first(where: { $0.id == selection }) {
                        ProviderDetails(model: model, provider: provider, reload: reload)
                            .id(provider.id)
                    } else {
                        ContentUnavailableView("Select a provider", systemImage: "cpu")
                    }
                }
            } else if loadError == nil {
                ProgressView("Loading providers…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let loadError {
                HStack {
                    Text(loadError).foregroundStyle(.red).textSelection(.enabled)
                    Button("Retry") { Task { await reload() } }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: RefreshKey(active: model.activeProviderID, signingIn: signIn != nil)) {
            await reload()
        }
        .onChange(of: signIn == nil) { if signIn == nil { signInError = nil } }
    }

    private struct RefreshKey: Equatable {
        let active: String?
        let signingIn: Bool
    }

    private func providerRow(_ provider: Synth.Provider) -> some View {
        let kind = ProviderKind(rawValue: provider.id)
        let active = model.activeProviderID == provider.id
        return VStack(alignment: .leading, spacing: 3) {
            Text(kind?.title ?? provider.id)
            if active {
                Text("In use").font(.caption).foregroundStyle(.secondary)
            } else if provider.connected {
                Text(kind?.authentication == .browser ? "Signed in" : "API key saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func signInControls(_ flow: Synth.SignIn) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(flow.url.isEmpty ? "Preparing browser sign-in…" : "Finish signing in in your browser.")
                if !flow.userCode.isEmpty {
                    Text("Enter code: \(flow.userCode)").monospaced().textSelection(.enabled)
                }
                if let signInError {
                    Text(signInError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            Spacer()
            if let url = URL(string: flow.url), url.scheme == "https", url.host != nil {
                Link("Open Sign-In Page", destination: url)
            }
            Button("Cancel Sign-In", action: cancelSignIn)
                .disabled(!model.canConfigure)
        }
        .padding(12)
    }

    private func cancelSignIn() {
        guard let session = model.sessionID else { return }
        signInError = nil
        Task {
            do {
                try await model.configure(in: session) { try await $0.cancelSignIn(in: $1) }
            } catch {
                signInError = error.localizedDescription
            }
        }
    }

    private func reload() async {
        guard model.canReadConfiguration, let session = model.sessionID, let client = model.client else { return }
        do {
            let current = try await client.providers(in: session)
            guard !Task.isCancelled, model.sessionID == session else { return }
            providers = current
            loadError = nil
            if selection == nil || !current.contains(where: { $0.id == selection }) {
                selection = current.first(where: \.active)?.id ?? current.first?.id
            }
        } catch where !Task.isCancelled && model.sessionID == session {
            loadError = error.localizedDescription
        } catch {}
    }
}

private struct ProviderDetails: View {
    let model: ConversationModel
    let provider: Synth.Provider
    let reload: () async -> Void
    @State private var endpoint: String?
    @State private var key = ""
    @State private var connectionError: String?
    @State private var noticeBeforeSignIn: String?
    @State private var attemptedSignIn = false
    @State private var confirmSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind?.title ?? provider.id).font(.headline)
            if let kind { connection(kind) }
            Divider()
            Text("Models").font(.headline)
            ModelBrowser(model: model, providerID: provider.id, readOnly: true)
            Spacer(minLength: 0)
            Text("Provider credentials are shared with the terminal client. Model selection remains per conversation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Sign out of \(kind?.title ?? provider.id)?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive, action: signOut)
        } message: {
            Text("Synth shares provider credentials with the terminal client.")
        }
    }

    private var kind: ProviderKind? { ProviderKind(rawValue: provider.id) }
    private var active: Bool { model.activeProviderID == provider.id }
    private var signingIn: Bool { model.state?.status?.signIn != nil }
    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func connection(_ kind: ProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if kind.hasEditableHost {
                TextField("Endpoint", text: Binding(get: { endpoint ?? provider.host }, set: { endpoint = $0 }))
            } else if kind.authentication != .browser {
                LabeledContent("Endpoint", value: provider.host)
            }
            if kind.authentication != .browser {
                SecureField("API key", text: $key, prompt: Text(keyPrompt(kind)))
            }
            HStack {
                Spacer()
                if kind.authentication == .browser && provider.connected && active {
                    Label("Signed in", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    Button("Sign Out…") { confirmSignOut = true }
                } else {
                    Button(connectTitle(kind)) { connect(kind) }
                        .disabled(kind.authentication == .requiredKey && !provider.connected && trimmedKey.isEmpty)
                }
            }
            if let connectionError {
                Text(connectionError).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            } else if attemptedSignIn, !active, let notice = model.state?.notices.last, notice != noticeBeforeSignIn {
                Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .disabled(!model.canConfigure || signingIn)
    }

    private func keyPrompt(_ kind: ProviderKind) -> String {
        if provider.connected { return "Leave blank to keep saved key" }
        return kind.authentication == .optionalKey ? "Optional" : "Required"
    }

    private func connectTitle(_ kind: ProviderKind) -> String {
        if kind.authentication == .browser { return provider.connected ? "Use Provider" : "Sign In…" }
        return active ? "Save & Reconnect" : "Connect"
    }

    private func signOut() {
        // ACP signs out the active OAuth provider, not an arbitrary catalog entry.
        guard active, let session = model.sessionID else { return }
        connectionError = nil
        Task {
            guard active else { return }
            do {
                try await model.configure(in: session) { try await $0.signOut(in: $1) }
                await reload()
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }

    private func connect(_ kind: ProviderKind) {
        guard let session = model.sessionID else { return }
        let host = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind.hasEditableHost, let host, !Self.isEndpoint(host) {
            connectionError = "Enter an HTTP or HTTPS endpoint without embedded credentials."
            return
        }
        let submittedKey = trimmedKey.isEmpty ? nil : trimmedKey
        noticeBeforeSignIn = model.state?.notices.last
        attemptedSignIn = kind.authentication == .browser && !provider.connected
        connectionError = nil
        key = ""
        Task {
            do {
                try await model.configure(in: session) { client, session in
                    try await client.connectProvider(provider.id, host: host, key: submittedKey, in: session)
                }
                endpoint = nil
            } catch {
                connectionError = error.localizedDescription
            }
            await reload()
        }
    }

    private static func isEndpoint(_ host: String) -> Bool {
        guard let url = URLComponents(string: host), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else { return false }
        return (scheme == "http" || scheme == "https") && url.user == nil && url.password == nil
    }
}
