import SynthProtocol

extension SynthClient {
    public func providers(in sessionID: String) async throws -> [Synth.Provider] {
        try requireConnected()
        return try await call("_synth/providers", ACP.SessionRef(sessionID), as: [Synth.Provider].self)
    }

    public func connectProvider(_ provider: String, host: String, key: String?, in sessionID: String) async throws {
        try requireConnected()
        let request = Synth.ConnectProvider(sessionID: sessionID, provider: provider, host: host, key: key)
        _ = try await call("_synth/connect_provider", request, as: ACP.Empty.self)
    }

    public func cancelSignIn(in sessionID: String) async throws {
        try requireConnected()
        _ = try await call("_synth/cancel_sign_in", ACP.SessionRef(sessionID), as: ACP.Empty.self)
    }

    public func signOut(in sessionID: String) async throws {
        try requireConnected()
        _ = try await call("_synth/sign_out", ACP.SessionRef(sessionID), as: ACP.Empty.self)
    }

    public func toggleMCP(_ name: String, in sessionID: String) async throws {
        try requireConnected()
        _ = try await call("_synth/toggle_mcp", Synth.ToggleMCP(sessionID: sessionID, name: name), as: ACP.Empty.self)
    }
}
