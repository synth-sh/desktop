import Foundation
import SynthClient
import SynthProtocol

struct ConversationHistory {
    let revision = UUID()
    let messages: [Synth.Message]
}

struct ConversationTranscript {
    struct Revision: Equatable {
        let session: UUID?
        let history: UUID?
        let busy: Bool
    }

    let revision: Revision
    let rows: [TranscriptActivity.Row]
    let firstSequence: UInt64?
    let lastSequence: UInt64?
    let hasOlderMessages: Bool

    init(revision: Revision, state: SessionState?, history: ConversationHistory?) {
        self.revision = revision
        let recent = state?.messages ?? []
        let older = if let history, let first = recent.first {
            history.messages.prefix { $0.seq < first.seq }
        } else {
            ArraySlice<Synth.Message>()
        }
        let messages = older.isEmpty ? recent : Array(older) + recent
        firstSequence = messages.first?.seq
        lastSequence = messages.last?.seq
        hasOlderMessages = (state?.dropped ?? 0) > UInt64(older.count)
        rows = TranscriptActivity.rows(
            for: messages, busy: revision.busy, planUpdates: state?.planUpdates ?? [:],
            steeringSequences: state?.steeringSequences ?? []
        )
    }
}

extension ConversationModel {
    var transcript: ConversationTranscript {
        let history = sessionID.flatMap { historyBySession[$0] }
        let state = self.state
        let revision = ConversationTranscript.Revision(
            session: state?.transcriptRevision, history: history?.revision, busy: busy
        )
        if let cachedTranscript, cachedTranscript.revision == revision { return cachedTranscript }
        let transcript = ConversationTranscript(revision: revision, state: state, history: history)
        cachedTranscript = transcript
        return transcript
    }
}
