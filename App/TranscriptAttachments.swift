import AppKit
import MarkdownEngine
import SwiftUI
import SynthClient
import SynthProtocol

struct UserMessageBody: View {
    @Environment(\.synthPalette) private var palette
    let message: Synth.Message
    let sessionID: String
    let model: ConversationModel
    @State private var preview: ComposerAttachment?
    @State private var error: String?
    @State private var loading: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !message.text.isEmpty {
                MarkdownView(text: linkedText, identifier: "\(sessionID):\(message.seq)") { url in
                    guard let path = FileReference.path(url: url),
                          let index = message.attachments.firstIndex(where: { $0.path == path }) else { return }
                    Task { await open(index) }
                }
            }
            ForEach(Array(message.attachments.enumerated()), id: \.offset) { index, item in
                Button {
                    Task { await open(index) }
                } label: {
                    Label(loading == index ? "Loading…" : item.path, systemImage: "doc.text")
                        .lineLimit(1).truncationMode(.middle)
                }
                .disabled(loading != nil)
                .help("Preview submitted content")
            }
            ForEach(0..<(message.imageCount ?? 0), id: \.self) { index in
                TranscriptImage(sequence: message.seq, index: index, sessionID: sessionID, model: model)
            }
            if let error { Text(error).font(.caption).foregroundStyle(palette.danger) }
        }
        .sheet(item: $preview) { AttachmentPreview(attachment: $0) }
    }

    private var linkedText: String {
        guard !message.attachments.isEmpty, message.text.contains("@") else { return message.text }
        return FileReference.transcript(
            message.text, attachedPaths: Set(message.attachments.map(\.path)),
            excluding: MarkdownSource.codeRanges(in: message.text)
        )
    }

    private func open(_ index: Int) async {
        guard loading == nil else { return }
        loading = index
        defer { loading = nil }
        error = nil
        let item = message.attachments[index]
        do {
            let text: String
            if item.contentBytes > item.content.utf8.count {
                guard let client = model.client else { throw SynthClient.Failure.disconnected }
                text = try await client.attachment(sequence: message.seq, index: index, in: sessionID)
            } else {
                text = item.content
            }
            preview = .init(name: item.path, body: .text(text))
        } catch { self.error = error.localizedDescription }
    }
}

private struct TranscriptImage: View {
    @Environment(\.synthPalette) private var palette
    let sequence: UInt64
    let index: Int
    let sessionID: String
    let model: ConversationModel
    @State private var thumbnail: CGImage?
    @State private var attachment: ComposerAttachment?
    @State private var preview: ComposerAttachment?
    @State private var error: String?
    @State private var revision = 0

    var body: some View {
        Group {
            if let thumbnail, let attachment {
                Button { preview = attachment } label: {
                    Image(decorative: thumbnail, scale: 2).resizable().scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 180, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview image \(index + 1)")
            } else if let error {
                VStack(alignment: .leading) {
                    Text(error).font(.caption).foregroundStyle(palette.danger)
                    Button("Retry image") { revision += 1 }
                }
            } else {
                ProgressView("Loading image…").controlSize(.small)
            }
        }
        .task(id: revision) { await load() }
        .sheet(item: $preview) { AttachmentPreview(attachment: $0) }
    }

    private func load() async {
        guard thumbnail == nil else { return }
        error = nil
        do {
            guard let client = model.client else { throw SynthClient.Failure.disconnected }
            let encoded = try await client.image(sequence: sequence, index: index, in: sessionID)
            let (data, picture) = try await Task.detached {
                guard let data = Data(base64Encoded: encoded),
                      let image = AttachmentImporter.thumbnail(data, maxPixels: 560) else {
                    throw ComposerError.invalidImage
                }
                return (data, image)
            }.value
            guard !Task.isCancelled else { return }
            attachment = .init(name: "Image \(index + 1)", body: .image(data))
            thumbnail = picture
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
