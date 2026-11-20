import SwiftUI
import SynthClient
import SynthProtocol

struct TranscriptActivityView: View {
    @Environment(\.synthPalette) private var palette
    let activity: TranscriptActivity
    let stream: Synth.Stream?
    let sessionID: String
    let status: Synth.Status?
    let model: ConversationModel
    @State private var expanded: Bool?

    private var isExpanded: Binding<Bool> {
        Binding(get: { expanded ?? !activity.finished }, set: { expanded = $0 })
    }

    private var hasPlan: Bool { !activity.steps.isEmpty }

    var body: some View {
        ActivityDisclosure(
            title: title,
            icon: hasPlan ? "checklist" : "waveform.path",
            detail: hasPlan ? "\(activity.completedCount) of \(activity.steps.count) complete" : nil,
            expansion: isExpanded
        ) {
            VStack(alignment: .leading, spacing: 4) {
                if !activity.otherEntries.isEmpty || (stream != nil && activity.activeStep == nil) {
                    VStack(alignment: .leading, spacing: 2) {
                        entries(activity.otherEntries)
                        if activity.activeStep == nil { liveReasoning }
                    }
                    .padding(.leading, hasPlan ? 14 : 0)
                }
                ForEach(activity.steps) { step in
                    PlanActivityStep(
                        step: step, active: step.id == activity.activeStep && !activity.finished,
                        hasActivity: !step.entries.isEmpty || (step.id == activity.activeStep && stream != nil)
                    ) {
                        entries(step.entries)
                        if step.id == activity.activeStep { liveReasoning }
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface.opacity(0.5), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border).allowsHitTesting(false) }
        .onChange(of: activity.finished) { _, finished in if finished { expanded = false } }
    }

    private var title: String {
        if hasPlan {
            if !activity.finished, let step = activity.currentStep { return step.text }
            return "Plan"
        }
        return "Activity"
    }

    @ViewBuilder
    private var liveReasoning: some View {
        if let stream, !stream.thinking.isEmpty {
            ReasoningActivity(text: stream.thinking, elapsed: nil, streaming: !stream.closed, load: nil)
                .id(stream.request)
        }
    }

    private func entries(_ values: [TranscriptActivity.Entry]) -> some View {
        ForEach(values) { entry in
            switch entry.content {
            case .assistant(let message, let showsText):
                AssistantActivity(message: message, sessionID: sessionID, model: model, showsText: showsText)
            case .tool(let tool, let index):
                let sequence = entry.id.sequence
                let position = SessionState.ToolPosition(sequence: sequence, index: index)
                let note = tool.status == "running" ? status?.toolNote(sequence: sequence, index: index) : nil
                ToolActivity(
                    tool: tool, note: note, startedAt: model.state?.runningTools[position],
                    load: resultLoader(tool, sequence: sequence, index: index)
                )
            }
        }
    }

    private func resultLoader(_ tool: Synth.ToolCall, sequence: UInt64, index: Int) -> ActivityBodyLoader? {
        guard tool.resultBytes > (tool.result?.utf8.count ?? 0) else { return nil }
        return { try await model.fullToolResult(sequence: sequence, call: index, in: sessionID) }
    }
}

private struct PlanActivityStep<Content: View>: View {
    @Environment(\.synthPalette) private var palette
    let step: TranscriptActivity.Step
    let active: Bool
    let hasActivity: Bool
    @ViewBuilder let content: Content
    @State private var expanded: Bool?

    private var isExpanded: Binding<Bool> {
        Binding(get: { expanded ?? active }, set: { expanded = $0 })
    }

    var body: some View {
        if hasActivity {
            ActivityDisclosure(
                title: step.text, icon: marker, tint: step.status.planColor(palette),
                detail: step.status.planLabel, muted: step.status == .pending, expansion: isExpanded
            ) {
                VStack(alignment: .leading, spacing: 3) { content }
                    .padding(.leading, 10)
                    .background(alignment: .leading) { Rectangle().fill(palette.border).frame(width: 1) }
                    .padding(.leading, 7)
            } trailing: {
                if let start = step.startedAt {
                    if let end = step.endedAt {
                        ActivityDuration(milliseconds: UInt64(max(0, end.timeIntervalSince(start)) * 1_000))
                    } else if active {
                        RunningDuration(start: start)
                    }
                }
            }
        } else {
            Label(step.text, systemImage: marker)
                .font(.callout)
                .foregroundStyle(step.status.planColor(palette))
                .padding(.vertical, 4)
                .accessibilityValue(step.status.planLabel)
        }
    }

    private var marker: String {
        switch step.status {
        case .pending: "circle"
        case .active: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }
}

struct AssistantActivity: View {
    let message: Synth.Message
    let sessionID: String
    let model: ConversationModel
    let showsText: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.thinking?.isEmpty == false || message.thinkingBytes > 0 {
                ReasoningActivity(
                    text: message.thinking ?? "", elapsed: message.thinkingMilliseconds, load: reasoningLoader
                )
            }
            if showsText, !message.text.isEmpty {
                MarkdownView(text: message.text, identifier: "\(sessionID):\(message.seq)")
            }
        }
    }

    private var reasoningLoader: ActivityBodyLoader? {
        guard message.thinkingBytes > (message.thinking?.utf8.count ?? 0) else { return nil }
        return { try await model.fullThinking(message, in: sessionID) }
    }
}

typealias ActivityBodyLoader = @MainActor () async throws -> String

private struct ReasoningActivity: View {
    let text: String
    let elapsed: UInt64?
    var streaming = false
    let load: ActivityBodyLoader?

    var body: some View {
        ActivityDisclosure(title: streaming ? "Thinking…" : "Reasoning", icon: "brain", muted: true) {
            ExpandableActivityBody(preview: text, load: load)
        } trailing: {
            if let elapsed { ActivityDuration(milliseconds: elapsed) }
        }
    }
}

private struct ToolActivity: View {
    @Environment(\.synthPalette) private var palette
    let tool: Synth.ToolCall
    let note: String?
    let startedAt: Date?
    let load: ActivityBodyLoader?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ActivityDisclosure(title: title, icon: icon, tint: tint, detail: statusLabel) {
                VStack(alignment: .leading, spacing: 8) {
                    ToolArgumentsView(
                        arguments: tool.arguments, showsDiff: tool.name == "edit" || tool.name == "write",
                        result: tool.result, applied: tool.status == "ok"
                    )
                    if tool.result?.isEmpty == false || load != nil {
                        ActivityDisclosure(title: "Output", expansion: nil) {
                            ExpandableActivityBody(preview: tool.result ?? "", load: load)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            } trailing: {
                if let elapsed = tool.elapsedMilliseconds {
                    ActivityDuration(milliseconds: elapsed)
                } else if tool.status == "running", let startedAt {
                    RunningDuration(start: startedAt)
                }
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(palette.muted)
                    .padding(.leading, 21)
                    .textSelection(.enabled)
            }
        }
    }

    private var title: String {
        let targetKeys = ["path", "command", "pattern", "url", "query", "prompt", "question"]
        let input = try? JSONSerialization.jsonObject(with: Data(tool.arguments.utf8)) as? [String: Any]
        let target = targetKeys.lazy.compactMap { input?[$0] as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let action = switch tool.name {
        case "bash", "shell": "Run"
        case "todo": "Update plan"
        case "web_search": "Search web"
        case "web_fetch": "Fetch"
        default: tool.name.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
        guard let target else { return action }
        let preview = String(target.prefix(240)).components(separatedBy: .newlines).joined(separator: " ")
        return "\(action)  \(preview)"
    }

    private var icon: String {
        switch tool.name {
        case "bash", "shell": "terminal"
        case "read": "doc.text"
        case "list": "folder"
        case "edit", "write": "pencil.line"
        case "grep", "glob", "web_search": "magnifyingglass"
        case "web_fetch": "globe"
        case "todo": "checklist"
        default: tool.name.hasPrefix("mcp") ? "puzzlepiece.extension" : "wrench"
        }
    }

    private var tint: Color {
        switch tool.status {
        case "running": palette.accent
        case "failed", "rejected": palette.danger
        default: palette.muted
        }
    }

    private var statusLabel: String {
        switch tool.status {
        case "pending": "Waiting"
        case "running": "Running"
        case "ok": "Done"
        case "failed": "Failed"
        case "rejected": "Declined"
        default: tool.status.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
    }
}
