import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import SwiftUI

enum MarkdownPresentation {
    private static let lightCode = HighlightJSBridge(autoSwitchAppearance: false)
    private static let darkCode = HighlightJSBridge(
        lightTheme: .githubDark, autoSwitchAppearance: false,
        lightBackground: NSColor(calibratedWhite: 0.13, alpha: 1)
    )
    private static let diffLanguages: [String: String] = [
        "swift": "swift", "zig": "zig", "css": "css", "json": "json", "sql": "sql",
        "yaml": "yaml", "yml": "yaml", "toml": "toml", "java": "java", "go": "go", "c": "c", "cpp": "cpp",
        "js": "javascript", "jsx": "javascript", "ts": "typescript", "tsx": "typescript",
        "py": "python", "rs": "rust", "rb": "ruby", "sh": "bash", "zsh": "bash", "html": "xml", "xml": "xml"
    ]

    static func configuration(
        _ palette: SynthPalette, colorScheme: ColorScheme, fitsContent: Bool = false
    ) -> MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration()
        configuration.theme.bodyText = NSColor(palette.foreground)
        configuration.theme.mutedText = NSColor(palette.muted)
        configuration.theme.disabledText = NSColor(palette.muted)
        configuration.theme.headingMarker = NSColor(palette.muted)
        configuration.theme.link = NSColor(palette.accent)
        configuration.theme.incompleteLink = NSColor(palette.muted)
        configuration.theme.strikethroughColor = NSColor(palette.muted)
        configuration.overscroll = .init(percent: 0, maxPoints: 0, minPoints: 0)
        configuration.textInsets = .init(horizontal: 4, vertical: 4)
        configuration.heightBehavior = fitsContent ? .fitsContent : .scrolls
        configuration.extensions = [StrikethroughExtension()]
        configuration.services = MarkdownEditorServices(syntaxHighlighter: colorScheme == .dark ? darkCode : lightCode)
        return configuration
    }

    static func openExternal(_ url: URL) {
        if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
    }

    static func highlightedLine(_ text: String, path: String, colorScheme: ColorScheme) -> AttributedString? {
        let fileExtension = (path as NSString).pathExtension.lowercased()
        guard !text.isEmpty, text.utf8.count <= 320, let language = diffLanguages[fileExtension] else { return nil }
        let bridge = colorScheme == .dark ? darkCode : lightCode
        guard let highlighted = bridge.highlight(code: text, language: language),
              var output = try? AttributedString(highlighted, including: \.appKit) else { return nil }
        for run in output.runs {
            if let color = run.appKit.foregroundColor {
                output[run.range].swiftUI.foregroundColor = Color(nsColor: color)
            }
        }
        return output
    }
}
