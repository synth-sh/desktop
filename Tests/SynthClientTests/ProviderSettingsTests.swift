import Foundation
import SynthClient
import SynthProtocol
import Testing

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["SYNTH_TEST_ENGINE"] != nil, "Run the fake provider harness"),
    .timeLimit(.minutes(1))
)
func providerChangesRefreshModelsAndKeepTheEffectiveEndpoint() async throws {
    let env = ProcessInfo.processInfo.environment
    let engine = try #require(env["SYNTH_TEST_ENGINE"])
    let endpoint = try #require(env["SYNTH_TEST_PROVIDER"])
    let fixture = try RouterFixture(engine: engine, provider: endpoint)
    let client = fixture.client()
    do {
        try await checkProviderChanges(client, cwd: fixture.first.path, endpoint: endpoint)
    } catch {
        await client.disconnect()
        try? FileManager.default.removeItem(at: fixture.root)
        throw error
    }
    await client.disconnect()
    try FileManager.default.removeItem(at: fixture.root)
}

private func checkProviderChanges(_ client: SynthClient, cwd: String, endpoint: String) async throws {
    _ = try await client.connect()
    let session = try #require(try await client.newSession(cwd: cwd).sessionId)
    let provider = "openai-compat"
    #expect(try await client.providers(in: session).first { $0.id == provider }?.host == endpoint)
    await #expect(throws: RPCError.self) {
        try await client.setModel("gpt-custom", provider: "openai", in: session)
    }
    #expect(try await client.providers(in: session).first(where: \.active)?.id == provider)
    try await client.connectProvider(provider, key: "fixture-rotated-key", in: session)
    #expect(try await client.providers(in: session).first { $0.id == provider }?.host == endpoint)
    try await expectProviderModels(["gpt-fixture-key"], provider: provider, client: client, session: session)

    let endpointURL = try #require(URL(string: endpoint))
    let server = endpointURL.deletingLastPathComponent()
    try await verifySettingsConnection(client, session: session, server: server, active: provider)

    let alternate = server.appending(path: "alternate/v1").absoluteString
    let before = await client.sessions[session]?.status?.model
    try await client.connectProvider(provider, host: alternate, key: nil, activate: false, in: session)
    try await expectProviderModels(
        ["gpt-fixture-other-endpoint", "gpt-fixture-small"], provider: provider, client: client, session: session
    )
    #expect(await client.sessions[session]?.status?.model == before)
    try await verifyModelSwitchWithLongHistory(client, session: session, provider: provider)
}

private func verifySettingsConnection(
    _ client: SynthClient, session: String, server: URL, active: String
) async throws {
    let model = try #require(await client.sessions[session]?.status?.model)
    try await client.connectProvider("ollama", host: server.absoluteString, key: nil, activate: false, in: session)
    try await expectProviderModels(["fixture-ollama"], provider: "ollama", client: client, session: session)
    #expect(try await client.providers(in: session).first(where: \.active)?.id == active)
    #expect(await client.sessions[session]?.status?.model == model)
    await #expect(throws: RPCError.self) {
        try await client.setModel("unavailable-ollama-model", provider: "ollama", in: session)
    }
    #expect(try await client.providers(in: session).first(where: \.active)?.id == active)
    #expect(await client.sessions[session]?.status?.model == model)
}

private func verifyModelSwitchWithLongHistory(
    _ client: SynthClient, session: String, provider: String
) async throws {
    try await client.setModel("gpt-fixture-other-endpoint", provider: provider, in: session)
    let history = String(repeating: "fixture context ", count: 9_000)
    #expect(try await client.prompt(history, in: session).stopReason == "end_turn")
    let original = try #require(await client.sessions[session]?.messages)

    try await client.setModel("gpt-fixture-small", provider: provider, in: session)
    try await client.fetchModels(in: session)
    _ = try await client.providers(in: session)
    #expect(await client.sessions[session]?.messages == original)

    #expect(try await client.prompt("This prompt should stop once.", in: session).stopReason == "max_turn_requests")
    try await client.fetchModels(in: session)
    _ = try await client.providers(in: session)
    let stopped = try #require(await client.sessions[session]?.messages)
    #expect(stopped.filter { $0.text.hasPrefix("Stopped: history is too large to compact safely") }.count == 1)
    #expect(Array(stopped.prefix(original.count)) == original)
}

private func expectProviderModels(
    _ expected: [String], provider: String, client: SynthClient, session: String, line: Int = #line
) async throws {
    _ = try await wait(line: line) {
        let models = await client.sessions[session]?.models?.offered.filter { $0.providerID == provider }.map(\.name)
        return models == expected ? true : nil
    }
}
