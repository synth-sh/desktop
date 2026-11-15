import Foundation
import SynthProtocol

extension SynthClient {
    public struct AttentionEvent: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case permission(RequestID)
            case question(RequestID)
            case inputResolved(RequestID)
            case turnCompleted
            case turnCancelled
            case turnFailed
            case turnHalted
            case sessionStopped

            public var requestID: RequestID? {
                switch self {
                case .permission(let id), .question(let id), .inputResolved(let id): id
                default: nil
                }
            }

            init(outcome: String?) {
                switch outcome {
                case "cancelled": self = .turnCancelled
                case "failed": self = .turnFailed
                case "halted": self = .turnHalted
                default: self = .turnCompleted
                }
            }
        }

        public let sessionID: String
        public let kind: Kind
    }

    public func attentionEvents() -> AsyncStream<AttentionEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AttentionEvent>.makeStream()
        attentionSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeAttentionSubscriber(id) }
        }
        return stream
    }

    private func removeAttentionSubscriber(_ id: UUID) {
        attentionSubscribers.removeValue(forKey: id)
    }

    func reportAttention(_ sessionID: String, _ kind: AttentionEvent.Kind) {
        let event = AttentionEvent(sessionID: sessionID, kind: kind)
        for subscriber in attentionSubscribers.values { subscriber.yield(event) }
    }

    func addInteraction(_ interaction: Interaction) {
        guard interactions.updateValue(interaction, forKey: interaction.id) == nil else { return }
        let kind: AttentionEvent.Kind = switch interaction {
        case .permission: .permission(interaction.id)
        case .question: .question(interaction.id)
        }
        reportAttention(interaction.sessionID, kind)
    }

    func removeInteraction(_ id: RequestID) {
        guard let interaction = interactions.removeValue(forKey: id) else { return }
        reportAttention(interaction.sessionID, .inputResolved(id))
    }

    func removeInteractions(for sessionID: String) {
        for interaction in interactions.values where interaction.sessionID == sessionID {
            removeInteraction(interaction.id)
        }
    }

    func acceptStatus(_ event: Synth.StatusUpdate) {
        let previous = sessions[event.sessionId]?.status?.finished
        sessions[event.sessionId, default: .init()].update(event.status)
        if let previous, event.status.finished > previous {
            reportAttention(event.sessionId, .init(outcome: event.status.outcome))
        }
    }

    func markSessionFailed(_ sessionID: String, error: any Error, report: Bool = false) {
        let newlyFailed = sessions[sessionID]?.failure == nil
        sessions[sessionID, default: .init()].disconnect(error.localizedDescription)
        removeInteractions(for: sessionID)
        if report && newlyFailed { reportAttention(sessionID, .sessionStopped) }
        changed()
    }
}
