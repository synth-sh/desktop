import AppKit

@MainActor
enum AboutPanel {
    static func show() {
        let version = Bundle.main.url(forResource: "SynthEngineVersion", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let engine = version.isEmpty ? "Engine version unavailable" : "Engine \(version)"
        let credits = NSMutableAttributedString(string: "\(engine)\n\n")
        credits.append(NSAttributedString(string: "GitHub", attributes: [.link: "https://github.com/synth-sh/desktop"]))
        credits.append(NSAttributedString(string: "  •  "))
        credits.append(NSAttributedString(string: "getsynth.sh", attributes: [.link: "https://getsynth.sh"]))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttributes(
            [.paragraphStyle: paragraph, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)],
            range: NSRange(location: 0, length: credits.length)
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
