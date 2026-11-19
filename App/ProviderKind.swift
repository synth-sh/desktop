// The engine's provider list supplies IDs and state, not display or form metadata.
enum ProviderKind: String {
    case ollama
    case ollamaCloud = "ollama-cloud"
    case openAI = "openai"
    case openAICompatible = "openai-compat"
    case copilot
    case chatGPT = "chatgpt"

    enum Authentication { case optionalKey, requiredKey, browser }

    var title: String {
        switch self {
        case .ollama: "Ollama"
        case .ollamaCloud: "Ollama Cloud"
        case .openAI: "OpenAI"
        case .openAICompatible: "OpenAI-compatible"
        case .copilot: "GitHub Copilot"
        case .chatGPT: "ChatGPT plan"
        }
    }

    var authentication: Authentication {
        switch self {
        case .ollama, .openAICompatible: .optionalKey
        case .ollamaCloud, .openAI: .requiredKey
        case .copilot, .chatGPT: .browser
        }
    }

    var hasEditableHost: Bool { authentication == .optionalKey }
    var allowsManualModel: Bool { authentication != .browser }
}
