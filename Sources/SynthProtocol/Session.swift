public enum ACP {
    public static let version = 1
    public static let synthVersion = 2

    public struct Empty: Codable, Sendable {
        public init() {}
    }

    public struct Metadata: Codable, Sendable {
        public struct Synth: Codable, Sendable {
            public let `protocol`: Int
        }

        public let synth: Synth?
    }

    public struct Initialize: Encodable, Sendable {
        public let protocolVersion = ACP.version
        public let clientCapabilities: JSONValue = .object([
            "elicitation": .object(["form": .object([:])])
        ])
        public let metadata: Metadata = Metadata(synth: .init(protocol: ACP.synthVersion))
        public let clientInfo = ["name": "synth-desktop"]

        private enum CodingKeys: String, CodingKey {
            case protocolVersion, clientCapabilities, clientInfo
            case metadata = "_meta"
        }

        public init() {}
    }

    public struct Initialized: Decodable, Sendable {
        public struct AgentInfo: Decodable, Sendable {
            public let name: String
            public let version: String?
        }

        public let protocolVersion: Int
        public let agentInfo: AgentInfo
        public let metadata: Metadata?

        private enum CodingKeys: String, CodingKey {
            case protocolVersion
            case agentInfo
            case metadata = "_meta"
        }
    }

    public struct SessionRef: Codable, Sendable {
        public let sessionId: String

        public init(_ sessionID: String) { sessionId = sessionID }
    }

    public struct Open: Encodable, Sendable {
        public let sessionId: String?
        public let cwd: String
        public let mcpServers: [Empty] = []

        public init(cwd: String, sessionID: String? = nil) {
            self.cwd = cwd
            sessionId = sessionID
        }
    }

    public struct Mode: Decodable, Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let description: String?
    }

    public struct Modes: Decodable, Equatable, Sendable {
        public let currentModeId: String
        public let availableModes: [Mode]
    }

    public struct SessionOpened: Decodable, Sendable {
        public let sessionId: String?
        public let modes: Modes?
        public let configOptions: [JSONValue]?
    }

    public struct List: Encodable, Sendable {
        public let cwd: String?
        public let cursor: String?

        public init(cwd: String?, cursor: String?) {
            self.cwd = cwd
            self.cursor = cursor
        }
    }

    public struct SessionInfo: Decodable, Identifiable, Sendable {
        public struct Metadata: Decodable, Sendable {
            public struct Stored: Decodable, Sendable {
                public let messages: UInt64
                public let updatedAt: Int64
                public let live: Bool

                private enum CodingKeys: String, CodingKey {
                    case messages
                    case updatedAt = "updated_at"
                    case live
                }
            }
            public let synth: Stored?
        }

        public let sessionId: String
        public let cwd: String
        public let title: String?
        public let updatedAt: String?
        public let metadata: Metadata?

        public var id: String { sessionId }

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case cwd
            case title
            case updatedAt
            case metadata = "_meta"
        }
    }

    public struct SessionList: Decodable, Sendable {
        public let sessions: [SessionInfo]
        public let nextCursor: String?
    }

    public struct Prompt: Encodable, Sendable {
        public let sessionId: String
        public let prompt: [Content]

        public init(sessionID: String, text: String) {
            self.init(sessionID: sessionID, content: [.text(text)])
        }

        public init(sessionID: String, content: [Content]) {
            sessionId = sessionID
            prompt = content
        }
    }

    public struct Prompted: Decodable, Equatable, Sendable {
        public let stopReason: String
    }

    public struct CancelRequest: Codable, Sendable {
        public let requestId: RequestID

        public init(_ id: RequestID) { requestId = id }
    }
}

public enum Synth {
    public struct PlanStep: Decodable, Equatable, Sendable {
        public enum Status: String, Sendable {
            case pending, active, done

            public init(_ value: String) {
                switch value {
                case "active", "in_progress": self = .active
                case "done", "completed": self = .done
                default: self = .pending
                }
            }
        }

        public let text: String
        public let status: Status

        public init(text: String, status: Status) {
            self.text = text
            self.status = status
        }

        public init(from decoder: any Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(WireText.self) {
                self.init(text: text.wrappedValue, status: .pending)
            } else {
                let fields = try decoder.container(keyedBy: CodingKeys.self)
                let text = try fields.decode(WireText.self, forKey: .text)
                let status = (try? fields.decode(String.self, forKey: .status)) ?? ""
                self.init(text: text.wrappedValue, status: .init(status))
            }
        }

        private enum CodingKeys: String, CodingKey { case text, status }
    }

    public struct Snapshot: Decodable, Sendable {
        public let sessionId: String
        public let status: Status
        public let messages: [Message]
        public let dropped: UInt64
        public let stream: Stream?
        public let skills: Skills?
    }

    public struct Status: Decodable, Equatable, Sendable {
        public let state: String
        public let label: String
        public let title: String
        public let root: String
        public let project: String
        public let branch: String
        public let agent: String
        private let approvalModeName: String?
        public let model: String
        public let provider: String
        public let providerID: String
        public let vision: Bool?
        public let providerMissing: Bool
        public let signIn: SignIn?
        public let signingOut: Bool?
        public let mcp: [MCPServer]?
        public let effort: String
        public let efforts: [String]
        public let request: UInt64?
        public let finished: UInt64
        public let outcome: String?
        public let steering: [String]
        public let pendingDescription: String
        public let todos: [PlanStep]?
        public let pendingSequence: UInt64?
        public let notes: [WireText]?

        public var isBusy: Bool { state != "idle" }
        public var approvalMode: ApprovalMode? { approvalModeName.flatMap(ApprovalMode.init(rawValue:)) }

        public func toolNote(sequence: UInt64, index: Int) -> String? {
            guard sequence == pendingSequence, let notes, notes.indices.contains(index),
                  !notes[index].wrappedValue.isEmpty else { return nil }
            return notes[index].wrappedValue
        }

        private enum CodingKeys: String, CodingKey {
            case state
            case label
            case title
            case root
            case project
            case branch
            case agent
            case approvalModeName = "approval_mode"
            case model
            case provider
            case providerID = "provider_id"
            case vision
            case providerMissing = "provider_missing"
            case signIn = "sign_in"
            case signingOut = "signing_out"
            case mcp
            case effort
            case efforts
            case request
            case finished
            case outcome
            case steering
            case pendingDescription = "pending_description"
            case todos
            case pendingSequence = "pending_seq"
            case notes
        }
    }

    public struct Message: Decodable, Equatable, Identifiable, Sendable {
        public let seq: UInt64
        public let role: String
        @WireText public var text: String
        private let thinkingText: WireText?
        public var thinking: String? { thinkingText?.wrappedValue }
        public let thinkingMilliseconds: UInt64?
        public let thinkingBytes: UInt64
        public let toolCalls: [ToolCall]
        public let toolName: String?
        public let toolCallID: String?
        public let attachments: [Attachment]
        public let imageCount: Int?

        public var id: UInt64 { seq }

        private enum CodingKeys: String, CodingKey {
            case seq
            case role
            case text
            case thinkingText = "thinking"
            case thinkingMilliseconds = "thinking_ms"
            case thinkingBytes = "thinking_bytes"
            case toolCalls = "tool_calls"
            case toolName = "tool_name"
            case toolCallID = "tool_call_id"
            case attachments
            case imageCount = "image_count"
        }
    }

    public struct Attachment: Decodable, Equatable, Sendable {
        @WireText public var path: String
        @WireText public var content: String
        public let contentBytes: UInt64

        private enum CodingKeys: String, CodingKey {
            case path
            case content
            case contentBytes = "content_bytes"
        }
    }

    public struct ToolCall: Decodable, Equatable, Sendable {
        public let id: String
        public let name: String
        @WireText public var arguments: String
        public let status: String
        private let resultText: WireText?
        public var result: String? { resultText?.wrappedValue }
        public let resultBytes: UInt64
        public let elapsedMilliseconds: UInt64?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case arguments
            case status
            case resultText = "result"
            case resultBytes = "result_bytes"
            case elapsedMilliseconds = "elapsed_ms"
        }
    }

    public struct Stream: Decodable, Equatable, Sendable {
        public let request: UInt64
        @WireText public var thinking: String
        @WireText public var text: String
        public var closed: Bool
    }

    public struct MessageUpdate: Decodable, Sendable {
        public let sessionId: String
        public let message: Message
    }

    public struct StatusUpdate: Decodable, Sendable {
        public let sessionId: String
        public let status: Status
    }

    public struct StreamUpdate: Decodable, Sendable {
        public let sessionId: String
        public let stream: Stream
    }

    public struct Notice: Decodable, Equatable, Sendable {
        public let sessionId: String
        @WireText public var text: String
    }
}
