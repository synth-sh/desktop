extension Synth {
    public struct BrowserRequest: Decodable, Sendable {
        public static let method = "_synth/browser"

        public enum Operation: String, Decodable, Sendable {
            case navigate, snapshot, click, fill, scroll
        }

        public struct Arguments: Decodable, Sendable {
            public let url: String?
            public let ref: String?
            public let text: String?
            public let direction: String?
        }

        public let sessionId: String
        public let operation: Operation
        public let arguments: Arguments
    }

    public struct BrowserResult: Codable, Sendable {
        public let content: String
        public let isError: Bool

        public init(_ content: String, isError: Bool = false) {
            self.content = content
            self.isError = isError
        }
    }
}
