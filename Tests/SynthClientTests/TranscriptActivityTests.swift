import Foundation
import SynthClient
import SynthProtocol
import Testing

@Test func assignsActivityToTheStepInForceAndPreservesTheFinalReply() throws {
    let start = Date(timeIntervalSince1970: 10)
    let next = Date(timeIntervalSince1970: 15)
    let initial = #"""
    {"items":[{"text":"Inspect","status":"active"},{"text":"Edit"},{"text":"Verify"}]}
    """#
    let updated = #"""
    {"items":[{"text":"Inspect","status":"done"},{"text":"Edit","status":"active"},{"text":"Verify"}]}
    """#
    let messages = try [
        message(1, role: "user", text: "Make the change"),
        message(2, thinking: "Plan the work", calls: [call("todo", initial), call("read", #"{"path":"App.swift"}"#)]),
        message(3, thinking: "Prepare the edit", calls: [call("todo", updated), call("edit", "{}")]),
        message(4, text: "Finished.", thinking: "Confirm the result")
    ]
    let live = TranscriptActivity.rows(for: Array(messages.dropLast()), busy: true, planUpdates: [2: start, 3: next])
    guard case .activity(let running) = live.last else {
        Issue.record("Expected the active plan")
        return
    }
    #expect(running.currentStep?.text == "Edit")
    #expect(running.steps.map(\.status) == [.done, .active, .pending])
    #expect(running.steps.map { $0.entries.count } == [3, 2, 0])
    #expect(running.steps.first?.startedAt == start)
    #expect(running.steps.first?.endedAt == next)
    #expect(!running.finished)

    let final = TranscriptActivity.rows(for: messages, busy: true)
    guard case .activity(let finished) = final[1], case .message(let reply, _) = final[2] else {
        Issue.record("Expected a plan followed by the final reply")
        return
    }
    #expect(finished.id == running.id)
    #expect(finished.finished)
    #expect(finished.currentStep?.entries.last?.id.sequence == 4)
    #expect(reply.text == "Finished.")
}

@Test func revisedPlansKeepRemovedActivityAndIgnoreFailedUpdates() throws {
    let messages = try [
        message(1, calls: [call("todo", #"{"items":[{"text":"Old","status":"active"}]}"#), call("read", "{}")]),
        message(2, calls: [call("todo", #"{"items":["Revised","Later"]}"#)]),
        message(3, calls: [call("todo", #"{"items":["Failed update"]}"#, status: "failed")])
    ]
    let rows = TranscriptActivity.rows(for: messages, busy: false)
    guard case .activity(let activity) = rows.last else {
        Issue.record("Expected an activity row")
        return
    }
    #expect(activity.steps.map(\.text) == ["Revised", "Later"])
    #expect(activity.otherEntries.count == 4)
    #expect(activity.finished)
}

@Test func queuedSteeringKeepsLaterCallsUnderTheActivePlanStep() throws {
    let messages = try [
        message(1, calls: [call("todo", #"{"items":[{"text":"Inspect","status":"active"}]}"#)]),
        message(2, role: "user", text: "Check the tests too"),
        message(3, calls: [call("bash", #"{"command":"swift test"}"#)])
    ]
    let rows = TranscriptActivity.rows(for: messages, busy: true, steeringSequences: [2])
    guard rows.count == 3, case .message(let steering, _) = rows[1], case .activity(let continuation) = rows[2] else {
        Issue.record("Expected the steering message followed by a plan continuation")
        return
    }
    #expect(steering.text == "Check the tests too")
    #expect(continuation.currentStep?.text == "Inspect")
    #expect(continuation.currentStep?.entries.map(\.id.sequence) == [3])
}

@Test func copiesOnlyUserTextOrTheFinalReplyWithItsCurrentPlan() throws {
    let plan = #"{"items":[{"text":"Read","status":"done"},{"text":"Edit","status":"active"},"Check"]}"#
    let messages = try [
        message(1, role: "user", text: "Check **this**"),
        message(2, text: "Intermediate commentary", thinking: "Internal reasoning", calls: [
            call("todo", #"{"items":["Replaced step"]}"#),
            call("mcp_fixture", #"{"hidden":"arguments"}"#),
            call("bash", #"{"command":"printf hidden"}"#)
        ]),
        message(3, role: "tool", text: "Hidden tool result"),
        message(4, calls: [call("todo", plan)]),
        message(5, text: "The **final** reply.\n", thinking: "Final private reasoning"),
        message(6, role: "user", text: "Next"),
        message(7, text: "A reply with no plan.")
    ]
    let rows = TranscriptActivity.rows(for: messages, busy: false)
    let checklist = "## Plan\n\n- [x] Read\n- [ ] Edit (in progress)\n- [ ] Check"
    #expect(rows.compactMap(\.messageCopyText) == [
        "Check **this**", "The **final** reply.\n\n\n" + checklist, "Next", "A reply with no plan."
    ])
    guard case .activity(let activity) = rows[1] else {
        Issue.record("Expected an activity row")
        return
    }
    #expect(activity.planCopyText == checklist)
}

@Test func previewsFileChangesWithOnlyKnownLineNumbers() throws {
    let edit = try #require(ToolFileChange(
        arguments: #"{"path":"App.swift","old":"unchanged\nold\n","new":"unchanged\nnew\nmore\n"}"#,
        result: "edited App.swift at line 40"
    ))
    let lines = try #require(edit.hunks.first?.lines)
    #expect(lines.map(\.kind) == [.context, .removal, .addition, .addition])
    #expect(lines.map(\.oldNumber) == [40, 41, nil, nil])
    #expect(lines.map(\.newNumber) == [40, nil, 41, 42])

    let write = try #require(ToolFileChange(arguments: #"{"path":"New.swift","content":"one\ntwo\n"}"#))
    #expect(write.hunks[0].lines.map(\.newNumber) == [1, 2])
    let empty = try #require(ToolFileChange(arguments: #"{"path":"Empty.swift","content":""}"#))
    #expect(empty.hunks[0].lines.isEmpty)

    let failed = try #require(ToolFileChange(
        arguments: #"{"path":"App.swift","old":"x","new":"y"}"#,
        result: "edit App.swift: edit 1 of 1: 'old' not found"
    ))
    #expect(failed.hunks[0].lines.allSatisfy { $0.oldNumber == nil && $0.newNumber == nil })
    #expect(ToolFileChange(arguments: #"{"path":"App.swift","old":"x"}"#) == nil)
}

@Test func readsSessionScopedPlanAndRunningNotesFromTheEngine() throws {
    let data = Data(#"""
    {
      "state":"running_tools","label":"Running","title":"First","root":"/project","project":"/project",
      "branch":"workspace","agent":"build","model":"fixture","provider":"fixture","provider_id":"fixture",
      "provider_missing":false,"effort":"","efforts":[],"finished":0,"pending_description":"",
      "todos":[{"text":"Read","status":"done"},{"text":"Write","status":"active"},{"text":"Check","status":"pending"}],
      "pending_seq":9,"notes":["", "Writing files"],"steering":["Check the tests too"]
    }
    """#.utf8)
    let status = try JSONDecoder().decode(Synth.Status.self, from: data)
    #expect(status.todos?.map(\.status) == [.done, .active, .pending])
    #expect(status.toolNote(sequence: 9, index: 1) == "Writing files")
    #expect(status.toolNote(sequence: 9, index: 0) == nil)
    #expect(status.toolNote(sequence: 8, index: 1) == nil)
    #expect(status.steering == ["Check the tests too"])
    #expect(status.root == "/project")
    #expect(status.branch == "workspace")
}

private func message(
    _ sequence: Int, role: String = "assistant", text: String = "", thinking: String = "", calls: [[String: Any]] = []
) throws -> Synth.Message {
    let data = try JSONSerialization.data(withJSONObject: [
        "seq": sequence, "role": role, "text": text, "thinking": thinking, "thinking_bytes": thinking.utf8.count,
        "tool_calls": calls, "attachments": []
    ])
    return try JSONDecoder().decode(Synth.Message.self, from: data)
}

private func call(_ name: String, _ arguments: String, status: String = "ok") -> [String: Any] {
    ["id": name, "name": name, "arguments": arguments, "status": status, "result_bytes": 0, "elapsed_ms": 100]
}
