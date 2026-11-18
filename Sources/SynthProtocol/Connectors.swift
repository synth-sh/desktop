extension Synth {
    public struct Provider: Decodable, Equatable, Identifiable, Sendable {
        public let id: String
        public let host: String
        public let connected: Bool
        public let active: Bool
    }

    public struct ConnectProvider: Encodable, Sendable {
        public let sessionId: String
        public let provider: String
        public let host: String
        public let key: String?

        public init(sessionID: String, provider: String, host: String, key: String?) {
            sessionId = sessionID
            self.provider = provider
            self.host = host
            self.key = key
        }
    }

    public struct SignIn: Decodable, Equatable, Sendable {
        public let url: String
        public let userCode: String

        private enum CodingKeys: String, CodingKey {
            case url
            case userCode = "user_code"
        }
    }

    public struct MCPServer: Decodable, Equatable, Identifiable, Sendable {
        public enum State: String, Decodable, Sendable {
            case off, connecting, connected, failed
        }

        public let name: String
        public let state: State
        public let reason: String

        public var id: String { name }
        public var isEnabled: Bool { state != .off }
    }

    public struct ToggleMCP: Encodable, Sendable {
        public let sessionId: String
        public let name: String

        public init(sessionID: String, name: String) {
            sessionId = sessionID
            self.name = name
        }
    }
}
