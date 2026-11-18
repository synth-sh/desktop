import Foundation

extension ACP {
    public enum Content: Encodable, Equatable, Sendable {
        case text(String)
        case image(data: String)
        case resource(name: String, text: String)

        private enum CodingKeys: String, CodingKey { case type, text, data, mimeType, resource }
        private struct Resource: Encodable {
            let uri: String
            let text: String
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let data):
                try container.encode("image", forKey: .type)
                try container.encode("image/png", forKey: .mimeType)
                try container.encode(data, forKey: .data)
            case .resource(let name, let text):
                try container.encode("resource", forKey: .type)
                try container.encode(Resource(uri: name, text: text), forKey: .resource)
            }
        }
    }
}

extension Synth {
    public struct Skill: Decodable, Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let description: String
        public let dir: String
    }

    public struct Skills: Decodable, Sendable {
        public let found: [Skill]
    }

    public struct AttachmentBody: Encodable, Sendable {
        public let sessionId: String
        public let seq: UInt64
        public let index: Int

        public init(sessionID: String, sequence: UInt64, index: Int) {
            sessionId = sessionID
            seq = sequence
            self.index = index
        }
    }
}
