import SwiftUI
import SynthClient
import SynthProtocol

enum TranscriptAnchor: Hashable {
    case message(UInt64)
    case activity(UInt64)
    case reasoning(UInt64)
    case stream(UInt64)
    case tail
}

struct TranscriptView: View {
    let sessionID: String
    let transcript: ConversationTranscript
    let stream: Synth.Stream?
    let status: Synth.Status?
    let notices: [String]
    let interactions: [Interaction]
    let model: ConversationModel
    @Binding var anchor: TranscriptAnchor?

    private let bottomTolerance: CGFloat = 24

    @State private var followsConversation = true
    @State private var userScrolling = false
    @State private var position = ScrollPosition(idType: TranscriptAnchor.self)
    @State private var followUpdate: Task<Void, Never>?

    private var liveReasoning: Synth.Stream? {
        guard let stream, !stream.thinking.isEmpty else { return nil }
        return stream
    }

    var body: some View {
        ScrollViewReader { reader in
            scrollView(reader)
        }
        .onDisappear { followUpdate?.cancel() }
    }

    private func scrollView(_ reader: ScrollViewProxy) -> some View {
        ScrollView { transcriptContent(reader) }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(followsConversation ? .bottom : .top, for: .sizeChanges)
        .scrollPosition($position, anchor: .top)
        .onChange(of: transcript.lastSequence) {
            if followsConversation, !userScrolling {
                position.scrollTo(edge: .bottom)
                followTail(using: reader)
            }
        }
        .onAppear {
            if let anchor, anchor != .tail {
                followsConversation = false
                position.scrollTo(id: anchor, anchor: .top)
            }
        }
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                height: geometry.contentSize.height, viewport: geometry.containerSize.height,
                distanceFromBottom: geometry.contentSize.height - geometry.visibleRect.maxY
            )
        } action: { previous, current in
            if userScrolling {
                followsConversation = current.distanceFromBottom <= bottomTolerance
            } else if previous.height != current.height || previous.viewport != current.viewport {
                followTail(using: reader)
            }
        }
        .onScrollPhaseChange { previous, phase, context in
            userScrolling = phase == .interacting || phase == .decelerating
            if userScrolling || previous == .interacting || previous == .decelerating {
                let geometry = context.geometry
                followsConversation = geometry.contentSize.height - geometry.visibleRect.maxY <= bottomTolerance
            }
        }
        .onChange(of: position.viewID(type: TranscriptAnchor.self)) { saveAnchor() }
        .onChange(of: followsConversation) { saveAnchor() }
        .overlay(alignment: .bottomTrailing) { jumpButton }
    }

    private func transcriptContent(_ reader: ScrollViewProxy) -> some View {
        let rows = transcript.rows
        return LazyVStack(alignment: .leading, spacing: 18) {
            if transcript.hasOlderMessages {
                Button("Load Earlier Messages") { Task { await model.loadOlder() } }
                    .disabled(model.loadingHistory.contains(sessionID))
            }
            ForEach(rows) { row in
                transcriptRow(row, last: rows.last?.id)
            }
            if let liveReasoning, !endsInActivity(rows.last) {
                TranscriptActivityView(
                    activity: .streaming(request: liveReasoning.request), stream: liveReasoning,
                    sessionID: sessionID, status: status, model: model
                )
                .id(TranscriptAnchor.reasoning(liveReasoning.request))
            }
            if let stream, !stream.text.isEmpty {
                StreamingMarkdown(text: stream.text, identifier: "\(sessionID):stream:\(stream.request)")
                    .id(TranscriptAnchor.stream(stream.request))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                        followTail(using: reader)
                    }
            }
            TranscriptNotices(notices: notices)
            ForEach(interactions) { interaction in
                InteractionCard(interaction: interaction, model: model)
            }
            QueuedSteering(messages: status?.steering ?? [])
            Color.clear.frame(height: 1).id(TranscriptAnchor.tail).accessibilityHidden(true)
        }
        .scrollTargetLayout()
        .frame(maxWidth: 730, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private func saveAnchor() {
        if followsConversation {
            if anchor != .tail { anchor = .tail }
        } else if let top = position.viewID(type: TranscriptAnchor.self), top != .tail, top != anchor {
            anchor = top
        }
    }

    @ViewBuilder
    private var jumpButton: some View {
        if !followsConversation {
            Button("Jump to Latest", systemImage: "arrow.down") {
                followsConversation = true
                position.scrollTo(edge: .bottom)
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .help("Jump to Latest")
            .padding()
        }
    }

    private func followTail(using reader: ScrollViewProxy) {
        guard followsConversation, !userScrolling, followUpdate == nil else { return }
        followUpdate = Task { @MainActor in
            defer { followUpdate = nil }
            await Task.yield()
            guard !Task.isCancelled, followsConversation, !userScrolling else { return }
            reader.scrollTo(TranscriptAnchor.tail, anchor: .bottom)
        }
    }

    private struct ScrollMetrics: Equatable {
        let height: CGFloat
        let viewport: CGFloat
        let distanceFromBottom: CGFloat
    }

    private func endsInActivity(_ row: TranscriptActivity.Row?) -> Bool {
        if case .activity? = row { return true }
        return false
    }

    @ViewBuilder
    private func transcriptRow(_ row: TranscriptActivity.Row, last: TranscriptActivity.ID?) -> some View {
        switch row {
        case .message(let message, _):
            TranscriptRow(message: message, copyText: row.messageCopyText, sessionID: sessionID, model: model)
                .id(TranscriptAnchor.message(message.seq))
        case .activity(let activity):
            if case .activity(let sequence) = activity.id {
                TranscriptActivityView(
                    activity: activity, stream: row.id == last ? liveReasoning : nil,
                    sessionID: sessionID, status: status, model: model
                )
                .id(TranscriptAnchor.activity(sequence))
            }
        }
    }
}

struct TranscriptNotices: View {
    @Environment(\.synthPalette) private var palette
    let notices: [String]

    var body: some View {
        ForEach(notices.indices, id: \.self) { index in
            Label(notices[index], systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(palette.muted)
                .textSelection(.enabled)
        }
    }
}

private struct TranscriptRow: View {
    @Environment(\.synthPalette) private var palette
    let message: Synth.Message
    let copyText: String?
    let sessionID: String
    let model: ConversationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch message.role {
            case "user":
                VStack(alignment: .leading, spacing: 6) {
                    Text("You").font(.caption.weight(.semibold)).foregroundStyle(palette.muted)
                        .frame(height: 20)
                        .padding(.trailing, 28)
                    UserMessageBody(message: message, sessionID: sessionID, model: model)
                }
                .overlay(alignment: .topTrailing) {
                    UserMessageCopyButton(text: copyText, message: message, sessionID: sessionID, model: model)
                }
                .padding(13)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 490, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            case "assistant":
                if !message.text.isEmpty {
                    MarkdownView(text: message.text, identifier: "\(sessionID):\(message.seq)")
                }
                if let copyText { MessageCopyButton(text: copyText) }
            case "summary":
                Text(message.text).font(.caption).foregroundStyle(palette.muted).textSelection(.enabled)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QueuedSteering: View {
    @Environment(\.synthPalette) private var palette
    let messages: [String]

    var body: some View {
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Queued", systemImage: "arrow.turn.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                ForEach(messages.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Text(verbatim: messages[index]).textSelection(.enabled)
                        MessageCopyButton(text: messages[index])
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: 490, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: 9))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
