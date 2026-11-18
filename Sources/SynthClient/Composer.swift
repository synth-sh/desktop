import SynthProtocol

extension SynthClient {
    public func prompt(_ text: String, in sessionID: String) async throws -> ACP.Prompted {
        try await prompt([.text(text)], in: sessionID)
    }

    public func prompt(_ content: [ACP.Content], in sessionID: String) async throws -> ACP.Prompted {
        try requireConnected()
        do {
            let request = ACP.Prompt(sessionID: sessionID, content: content)
            return try await call("session/prompt", request, as: ACP.Prompted.self)
        } catch LineFramer.Failure.oversized {
            throw ComposerError.payloadTooLarge
        } catch let error as RPCError where error.code == -32603 &&
            ["the session's agent stopped", "no such session"].contains(error.message) {
            markSessionFailed(sessionID, error: error, report: true)
            throw error
        }
    }

    public func files(in sessionID: String) async throws -> [String] {
        try requireConnected()
        return try await call("_synth/files", ACP.SessionRef(sessionID), as: [WireText].self).map(\.wrappedValue)
    }

    public func compact(in sessionID: String) async throws {
        try requireConnected()
        _ = try await call("_synth/compact", ACP.SessionRef(sessionID), as: ACP.Empty.self)
    }

    public func attachment(sequence: UInt64, index: Int, in sessionID: String) async throws -> String {
        try requireConnected()
        return try await call(
            "_synth/load_attachment", Synth.AttachmentBody(sessionID: sessionID, sequence: sequence, index: index),
            as: WireText.self
        ).wrappedValue
    }

    public func image(sequence: UInt64, index: Int, in sessionID: String) async throws -> String {
        try requireConnected()
        return try await call(
            "_synth/load_image", Synth.AttachmentBody(sessionID: sessionID, sequence: sequence, index: index),
            as: String.self
        )
    }
}
