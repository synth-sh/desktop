import Foundation
import SynthProtocol

public struct TranscriptActivity: Equatable, Identifiable, Sendable {
    public enum Identifier: Hashable, Sendable {
        case message(UInt64)
        case activity(UInt64)
        case stream(UInt64)
    }

    public struct Entry: Equatable, Identifiable, Sendable {
        public enum Content: Equatable, Sendable {
            case assistant(Synth.Message, showsText: Bool)
            case tool(Synth.ToolCall, index: Int)
        }

        public struct Identifier: Hashable, Sendable {
            public let sequence: UInt64
            public let call: Int?
        }

        public let id: Identifier
        public let content: Content
    }

    public struct Step: Equatable, Identifiable, Sendable {
        public struct Identifier: Hashable, Sendable {
            let text: String
            let occurrence: Int
        }

        public let id: Identifier
        public var text: String { id.text }
        public fileprivate(set) var status: Synth.PlanStep.Status
        public fileprivate(set) var entries: [Entry] = []
        public fileprivate(set) var startedAt: Date?
        public fileprivate(set) var endedAt: Date?
    }

    public let id: Identifier
    public private(set) var steps: [Step] = []
    public private(set) var otherEntries: [Entry] = []
    public private(set) var finished = false
    public private(set) var activeStep: Step.ID?

    public var completedCount: Int { steps.filter { $0.status == .done }.count }
    public var currentStep: Step? { steps.first { $0.id == activeStep } }

    public enum Row: Equatable, Identifiable, Sendable {
        case message(Synth.Message)
        case activity(TranscriptActivity)

        public var id: Identifier {
            switch self {
            case .message(let message): .message(message.seq)
            case .activity(let activity): activity.id
            }
        }
    }

    public static func rows(
        for messages: [Synth.Message], busy: Bool, planUpdates: [UInt64: Date] = [:],
        steeringSequences: Set<UInt64> = []
    ) -> [Row] {
        var rows: [Row] = []
        var activity: Self?

        for message in messages {
            switch message.role {
            case "assistant" where !message.toolCalls.isEmpty || Self.hasReasoning(message):
                if activity == nil { activity = Self(id: .activity(message.seq)) }
                activity?.append(message, at: planUpdates[message.seq])
                if message.toolCalls.isEmpty, !message.text.isEmpty, var current = activity {
                    current.finished = true
                    rows.append(.activity(current))
                    activity = nil
                    rows.append(.message(message))
                }
            case "assistant", "user", "summary":
                var continuation: Self?
                if var current = activity {
                    current.finished = true
                    rows.append(.activity(current))
                    if steeringSequences.contains(message.seq), !current.steps.isEmpty {
                        continuation = current.continued(after: message.seq)
                    }
                }
                rows.append(.message(message))
                activity = continuation
            default:
                continue
            }
        }
        if var activity {
            activity.finished = !busy
            rows.append(.activity(activity))
        }
        return rows
    }

    public static func streaming(request: UInt64) -> Self { Self(id: .stream(request)) }

    private func continued(after sequence: UInt64) -> Self {
        var continuation = Self(id: .activity(sequence))
        continuation.activeStep = activeStep
        continuation.steps = steps.map { step in
            var step = step
            step.entries = []
            return step
        }
        return continuation
    }

    private static func hasReasoning(_ message: Synth.Message) -> Bool {
        message.thinkingBytes > 0 || message.thinking?.isEmpty == false
    }

    private mutating func append(_ message: Synth.Message, at date: Date?) {
        let sequence = message.seq
        let showsText = !message.toolCalls.isEmpty
        if Self.hasReasoning(message) || (showsText && !message.text.isEmpty) {
            add(.init(id: .init(sequence: sequence, call: nil), content: .assistant(message, showsText: showsText)))
        }

        let previousStep = activeStep
        let updates = message.toolCalls.filter { $0.name == "todo" && $0.status == "ok" }
        for update in updates { apply(Self.plan(from: update.arguments), at: date) }

        for (index, call) in message.toolCalls.enumerated() {
            let entry = Entry(id: .init(sequence: sequence, call: index), content: .tool(call, index: index))
            add(entry, step: activeStep ?? (call.name == "todo" ? previousStep : nil))
        }
    }

    private mutating func add(_ entry: Entry, step: Step.ID? = nil) {
        if let index = steps.firstIndex(where: { $0.id == (step ?? activeStep) }) {
            steps[index].entries.append(entry)
        } else {
            otherEntries.append(entry)
        }
    }

    private mutating func apply(_ plan: [Synth.PlanStep], at date: Date?) {
        var occurrences: [String: Int] = [:]
        var previous = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
        var next: [Step] = []
        for item in plan {
            let occurrence = occurrences[item.text, default: 0]
            occurrences[item.text] = occurrence + 1
            let id = Step.ID(text: item.text, occurrence: occurrence)
            var step = previous.removeValue(forKey: id) ?? Step(id: id, status: .pending)
            if step.status != .active, item.status == .active {
                step.startedAt = date
                step.endedAt = nil
            } else if step.status == .active, item.status != .active {
                step.endedAt = date
            }
            step.status = item.status
            next.append(step)
        }
        activeStep = next.first { $0.status == .active }?.id
        otherEntries.append(contentsOf: steps.filter { previous[$0.id] != nil }.flatMap(\.entries))
        steps = next
    }

    private static func plan(from arguments: String) -> [Synth.PlanStep] {
        guard let input = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let items = input["items"] as? [Any] else { return [] }
        var plan: [Synth.PlanStep] = []
        var hasActive = false
        for item in items {
            let fields = item as? [String: Any]
            guard let raw = item as? String ?? fields?["text"] as? String else { continue }
            let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
            guard !text.isEmpty else { continue }
            let status = Synth.PlanStep.Status(fields?["status"] as? String ?? "")
            let normalized = status == .active && hasActive ? .pending : status
            let bytes = text.utf8.prefix(120)
            // The engine can split a UTF-8 scalar when it truncates a step.
            // swiftlint:disable:next optional_data_string_conversion
            let clipped = String(decoding: bytes, as: UTF8.self)
            plan.append(.init(text: clipped, status: normalized))
            hasActive = hasActive || status == .active
            if plan.count == 32 { break }
        }
        return plan
    }
}
