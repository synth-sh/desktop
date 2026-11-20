import Foundation
import SynthClient
import SynthProtocol
import Testing

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["SYNTH_TEST_ENGINE"] != nil, "Run the fake provider harness"),
    .timeLimit(.minutes(1))
)
func approvalModesAreSessionScopedAndReflectEngineFallback() async throws {
    let environment = ProcessInfo.processInfo.environment
    let fixture = try RouterFixture(
        engine: #require(environment["SYNTH_TEST_ENGINE"]), provider: #require(environment["SYNTH_TEST_PROVIDER"])
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let client = fixture.client()
    do {
        try await verifyApprovalModes(fixture, client: client)
    } catch {
        await client.disconnect()
        throw error
    }
    await client.disconnect()
}

private func verifyApprovalModes(_ fixture: RouterFixture, client: SynthClient) async throws {
    _ = try await client.connect()
    let first = try #require(try await client.newSession(cwd: fixture.first.path).sessionId)
    let second = try #require(try await client.newSession(cwd: fixture.second.path).sessionId)
    #expect(await client.sessions[first]?.status?.approvalMode == .ask)
    #expect(await client.sessions[second]?.status?.approvalMode == .ask)

    try await client.setApprovalMode(.auto, in: first)
    _ = try await wait { await client.sessions[first]?.status?.approvalMode == .auto ? true : nil }
    #expect(await client.sessions[second]?.status?.approvalMode == .ask)
    try await client.setApprovalMode(.all, in: second)
    _ = try await wait { await client.sessions[second]?.status?.approvalMode == .all ? true : nil }
    #expect(await client.sessions[first]?.status?.approvalMode == .auto)

    for _ in 0..<3 {
        #expect(try await client.prompt("block fixture auto approval", in: first).stopReason == "end_turn")
    }
    _ = try await wait { await client.sessions[first]?.status?.approvalMode == .ask ? true : nil }
    let blocked = await client.sessions[first]?.messages.flatMap(\.toolCalls).filter { $0.status == "rejected" }
    #expect(blocked?.count == 3)
    #expect(await client.sessions[second]?.status?.approvalMode == .all)

    try await client.setApprovalMode(.ask, in: second)
    _ = try await wait { await client.sessions[second]?.status?.approvalMode == .ask ? true : nil }
}
