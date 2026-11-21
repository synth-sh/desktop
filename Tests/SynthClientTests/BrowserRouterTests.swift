import Foundation
import SynthClient
import SynthProtocol
import Testing

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["SYNTH_TEST_ENGINE"] != nil, "Run the fake provider harness"),
    .timeLimit(.minutes(1))
)
@MainActor
func routesBrowserToolsToTheOptedInChatAndCancelsPendingCalls() async throws {
    let env = ProcessInfo.processInfo.environment
    let fixture = try RouterFixture(
        engine: #require(env["SYNTH_TEST_ENGINE"]), provider: #require(env["SYNTH_TEST_PROVIDER"])
    )
    let probe = BrowserProbe()
    let desktop = fixture.client(browser: probe.handle)
    let other = fixture.client()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    do {
        try await desktop.connect()
        let first = try #require(try await desktop.newSession(cwd: fixture.first.path).sessionId)
        let second = try #require(try await desktop.newSession(cwd: fixture.second.path).sessionId)
        #expect(try await desktop.prompt("check browser tools", in: first).stopReason == "end_turn")
        #expect(await desktop.sessions[first]?.messages.contains { $0.text == "Browser tools offered" } == true)
        #expect(try await desktop.prompt("inspect fixture browser", in: second).stopReason == "end_turn")
        #expect(probe.sessions == [second])
        #expect(await desktop.sessions[second]?.messages.contains { $0.text == "Fixture page" } == true)
        try await verifyBrowserCancellation(probe: probe, desktop: desktop, sessionID: first)

        try await other.connect()
        _ = try await other.loadSession(first, cwd: fixture.first.path)
        #expect(try await other.prompt("check browser tools", in: first).stopReason == "end_turn")
        #expect(await other.sessions[first]?.messages.contains { $0.text == "Browser tools omitted" } == true)
        #expect(probe.sessions == [second, first])
    } catch {
        await other.disconnect()
        await desktop.disconnect()
        throw error
    }
    await other.disconnect()
    await desktop.disconnect()
}

@MainActor
private func verifyBrowserCancellation(probe: BrowserProbe, desktop: SynthClient, sessionID: String) async throws {
    probe.shouldWait = true
    let turn = Task { try await desktop.prompt("cancel fixture browser", in: sessionID) }
    _ = try await wait { await probe.sessions.last == sessionID ? true : nil }
    try await desktop.cancelTurn(in: sessionID)
    #expect(try await turn.value.stopReason == "cancelled")
    _ = try await wait { await probe.didCancel ? true : nil }
}

@MainActor
private final class BrowserProbe {
    var sessions: [String] = []
    var shouldWait = false
    private(set) var didCancel = false

    func handle(_ request: Synth.BrowserRequest) async -> Synth.BrowserResult {
        sessions.append(request.sessionId)
        #expect(request.operation == .snapshot)
        if shouldWait {
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                didCancel = Task.isCancelled
            }
        }
        return .init("Fixture page")
    }
}
