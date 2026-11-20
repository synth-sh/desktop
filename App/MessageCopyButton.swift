import AppKit
import SwiftUI
import SynthClient
import SynthProtocol

struct MessageCopyButton: View {
    @Environment(\.synthPalette) private var palette
    @State private var result: ResultState = .idle
    @State private var copying: Task<Void, Never>?
    let label: String
    let copy: @MainActor () async throws -> Void

    init(label: String = "Copy message", copy: @escaping @MainActor () async throws -> Void) {
        self.label = label
        self.copy = copy
    }

    init(text: String, label: String = "Copy message") {
        self.init(label: label) { try Self.write([text as NSString]) }
    }

    var body: some View {
        Button {
            result = .idle
            copying = Task {
                defer { if !Task.isCancelled { copying = nil } }
                do {
                    try await copy()
                    if !Task.isCancelled { result = .copied }
                } catch where !Task.isCancelled {
                    result = .failed(error.localizedDescription)
                } catch {}
            }
        } label: {
            Image(systemName: result.icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(copying != nil)
        .accessibilityLabel(label)
        .accessibilityValue(result.feedback ?? "")
        .help(result.feedback ?? label)
        .task(id: result) {
            guard result != .idle else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { result = .idle }
        }
        .onDisappear {
            copying?.cancel()
            copying = nil
        }
    }

    private var color: Color {
        switch result {
        case .idle: palette.muted
        case .copied: palette.success
        case .failed: palette.danger
        }
    }

    static func write(_ items: [any NSPasteboardWriting]) throws {
        try Task.checkCancellation()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else { throw ClipboardWriteFailed() }
    }

    private enum ResultState: Equatable {
        case idle, copied, failed(String)

        var icon: String {
            switch self {
            case .idle: "doc.on.doc"
            case .copied: "checkmark"
            case .failed: "exclamationmark.circle"
            }
        }

        var feedback: String? {
            switch self {
            case .idle: nil
            case .copied: "Copied"
            case .failed(let message): message
            }
        }
    }
}

struct UserMessageCopyButton: View {
    let text: String?
    let message: Synth.Message
    let sessionID: String
    let model: ConversationModel

    var body: some View {
        if let text {
            MessageCopyButton(text: text)
        } else if !message.attachments.isEmpty || (message.imageCount ?? 0) > 0 {
            MessageCopyButton { try await copyAttachments() }
        }
    }

    private func copyAttachments() async throws {
        guard let client = model.client else { throw SynthClient.Failure.disconnected }
        var items: [any NSPasteboardWriting] = []
        for (index, item) in message.attachments.enumerated() {
            let text = if item.contentBytes > item.content.utf8.count {
                try await client.attachment(sequence: message.seq, index: index, in: sessionID)
            } else {
                item.content
            }
            items.append(text as NSString)
        }
        for index in 0..<(message.imageCount ?? 0) {
            let encoded = try await client.image(sequence: message.seq, index: index, in: sessionID)
            guard let data = Data(base64Encoded: encoded), let image = NSImage(data: data) else {
                throw ComposerError.invalidImage
            }
            items.append(image)
        }
        try MessageCopyButton.write(items)
    }
}

private struct ClipboardWriteFailed: LocalizedError {
    var errorDescription: String? { "Couldn’t write to the clipboard." }
}
