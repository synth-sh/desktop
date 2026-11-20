import Foundation
import SynthProtocol

public struct SessionState: Sendable {
    public private(set) var skills: [Synth.Skill] = []
    public private(set) var status: Synth.Status?
    public private(set) var messages: [Synth.Message] = []
    public private(set) var dropped: UInt64 = 0
    public private(set) var models: Synth.Models?
    public private(set) var notices: [String] = []
    public internal(set) var failure: String?
    public private(set) var planUpdates: [UInt64: Date] = [:]
    public private(set) var runningTools: [ToolPosition: Date] = [:]
    public private(set) var steeringSequences: Set<UInt64> = []
    private var streaming: Synth.Stream?

    public struct ToolPosition: Hashable, Sendable {
        public let sequence: UInt64
        public let index: Int

        public init(sequence: UInt64, index: Int) {
            self.sequence = sequence
            self.index = index
        }
    }

    public var stream: Synth.Stream? {
        guard let streaming, streaming.request == status?.request else { return nil }
        return streaming
    }

    mutating func replace(with snapshot: Synth.Snapshot) {
        skills = snapshot.skills?.found ?? []
        status = snapshot.status
        messages = snapshot.messages
        dropped = snapshot.dropped
        streaming = snapshot.stream
        failure = nil
        runningTools = [:]
        if let sequence = status?.pendingSequence,
           let message = messages.last(where: { $0.seq == sequence }) {
            trackRunningTools(in: message, at: .now)
        }
    }

    mutating func update(_ message: Synth.Message, appended: Bool) {
        if let index = messages.lastIndex(where: { $0.seq == message.seq }) {
            messages[index] = message
        } else if appended {
            messages.append(message)
            if message.role == "user", status?.isBusy == true, status?.steering.contains(message.text) == true {
                steeringSequences.insert(message.seq)
            }
        }
        if appended && message.role == "assistant" { streaming = nil }
        let now = Date.now
        if planUpdates[message.seq] == nil,
           message.toolCalls.contains(where: { $0.name == "todo" && $0.status == "ok" }) {
            planUpdates[message.seq] = now
        }
        trackRunningTools(in: message, at: now)
    }

    private mutating func trackRunningTools(in message: Synth.Message, at date: Date) {
        for (index, call) in message.toolCalls.enumerated() {
            let position = ToolPosition(sequence: message.seq, index: index)
            if call.status == "running" {
                if runningTools[position] == nil { runningTools[position] = date }
            } else {
                runningTools[position] = nil
            }
        }
    }

    mutating func append(_ delta: Synth.Stream) {
        if streaming?.request != delta.request {
            streaming = delta
        } else {
            streaming?.text += delta.text
            streaming?.thinking += delta.thinking
            if delta.closed { streaming?.closed = true }
        }
    }

    mutating func update(_ status: Synth.Status) {
        self.status = status
        if streaming?.request != status.request { streaming = nil }
    }

    mutating func update(_ models: Synth.Models) {
        self.models = models
    }

    mutating func notice(_ text: String) {
        notices.append(text)
        if notices.count > 50 { notices.removeFirst() }
    }

    mutating func disconnect(_ message: String?) {
        streaming = nil
        models = nil
        runningTools = [:]
        failure = message
    }
}
