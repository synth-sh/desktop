import Foundation
import SynthClient
import SynthProtocol
import Testing

@Test(.timeLimit(.minutes(1)))
func reportsLiveAttentionInWireOrder() async throws {
    let script = #"""
    IFS= read -r handshake
    printf '%s%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentInfo":{"name":"synth"},' \
      '"_meta":{"synth":{"protocol":2}}}}'
    IFS= read -r open
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"sessionId":"a"}}'
    printf '%s\n' "$@"
    """#
    let client = SynthClient(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", script, "fixture"] + (try attentionUpdates())
    )
    let events = await client.attentionEvents()
    try await client.connect()
    _ = try await client.newSession(cwd: "/fixture")
    var iterator = events.makeAsyncIterator()
    let expected: [(String, SynthClient.AttentionEvent.Kind)] = [
        ("a", .permission(.number(20))), ("b", .question(.number(21))), ("a", .inputResolved(.number(20))),
        ("a", .turnCompleted), ("b", .turnCancelled), ("a", .turnFailed), ("a", .turnHalted),
        ("a", .turnCompleted), ("a", .sessionStopped), ("b", .inputResolved(.number(21))), ("b", .sessionStopped)
    ]
    for (sessionID, kind) in expected {
        let event = try #require(await iterator.next())
        #expect(event.sessionID == sessionID)
        #expect(event.kind == kind)
    }
}

private func attentionUpdates() throws -> [String] {
    let fixture = try #require(
        Bundle.module.url(forResource: "stream", withExtension: "jsonl", subdirectory: "Fixtures")
    )
    let data = try Data(contentsOf: fixture).split(separator: 0x0a)
    let original = try #require(JSONSerialization.jsonObject(with: Data(data[0])) as? [String: Any])
    let params = try #require(original["params"] as? [String: Any])
    let baseline = try #require(params["status"] as? [String: Any])

    func status(_ session: String, _ finished: Int, _ outcome: String? = nil, snapshot: Bool = false) throws -> String {
        var status = baseline
        status["finished"] = finished
        status["outcome"] = outcome
        status["state"] = outcome == nil ? "thinking" : "idle"
        var params: [String: Any] = ["sessionId": session, "status": status]
        if snapshot {
            params["messages"] = []
            params["dropped"] = 0
        }
        let message: [String: Any] = [
            "jsonrpc": "2.0", "method": snapshot ? "_synth/snapshot" : "_synth/status", "params": params
        ]
        return try #require(String(bytes: JSONSerialization.data(withJSONObject: message), encoding: .utf8))
    }

    let permission = [
        #"{"jsonrpc":"2.0","id":20,"method":"session/request_permission","params":{"sessionId":"a","#,
        #""toolCall":{"toolCallId":"call-1"},"options":[]}}"#
    ].joined()
    let question = [
        #"{"jsonrpc":"2.0","id":21,"method":"elicitation/create","params":{"sessionId":"b","mode":"form","#,
        #""message":"Choose","requestedSchema":{"type":"object","properties":{},"required":[]}}}"#
    ].joined()
    let withdraw = #"{"jsonrpc":"2.0","method":"$/cancel_request","params":{"requestId":20}}"#
    let stopped = #"{"jsonrpc":"2.0","method":"_synth/session_stopped","params":{"sessionId":"a"}}"#
    return try [
        status("a", 9, "done", snapshot: true), status("a", 9, "done"),
        status("b", 0, snapshot: true), permission, permission, question, withdraw, withdraw,
        status("a", 10, "done"), status("a", 10, "done"), status("b", 1, "cancelled"),
        status("a", 11, "failed"), status("a", 12, "halted"),
        status("a", 0, snapshot: true), status("a", 1, "done"),
        status("b", 1), stopped, stopped
    ]
}
