import Foundation
import SynthProtocol

public struct ComposerAttachment: Identifiable, Equatable, Sendable {
    public enum Body: Equatable, Sendable {
        case text(String)
        case image(Data)
    }

    public let id: UUID
    public let name: String
    public let body: Body

    public init(id: UUID = UUID(), name: String, body: Body) {
        self.id = id
        self.name = name
        self.body = body
    }

    public var isImage: Bool {
        if case .image = body { return true }
        return false
    }
}

public struct ComposerDraft: Equatable, Sendable {
    public var markdown: String
    public var attachments: [ComposerAttachment]

    public init(markdown: String = "", attachments: [ComposerAttachment] = []) {
        self.markdown = markdown
        self.attachments = attachments
    }

    public var isEmpty: Bool {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }

    public var hasImages: Bool {
        attachments.contains(where: \.isImage) || FileReference.mentionsImage(in: FileReference.prompt(markdown))
    }

    public var content: [ACP.Content] {
        [.text(FileReference.prompt(markdown))] + attachments.map { attachment in
            switch attachment.body {
            case .text(let text): .resource(name: attachment.name, text: text)
            case .image(let data): .image(data: data.base64EncodedString())
            }
        }
    }

    public static func collapsesPaste(_ text: String) -> Bool {
        text.utf8.count >= 400 || text.utf8.lazy.filter { $0 == 10 }.prefix(3).count == 3
    }
}

public enum ComposerError: LocalizedError, Equatable {
    case payloadTooLarge
    case fileTooLarge
    case unsupportedFile
    case invalidImage
    case compactWithAttachments
    case missingReference(String)
    case linkedFileTooLarge(path: String, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: "This message exceeds the 16 MiB transport limit. Remove an attachment and try again."
        case .fileTooLarge: "Text attachments must be at most 1 MiB and images at most 10 MiB."
        case .unsupportedFile: "Attach a UTF-8 text file or an image."
        case .invalidImage: "This image cannot be decoded or is too large to preview."
        case .compactWithAttachments: "Choose /compact from the slash menu to keep this draft and its attachments."
        case .missingReference(let path): "Cannot attach \(path) from the current project."
        case .linkedFileTooLarge(let path, let limit):
            "\(path) exceeds the \(limit.formatted(.byteCount(style: .binary))) limit for linked files."
        }
    }
}
